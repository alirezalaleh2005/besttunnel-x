#!/usr/bin/env bash
#
# BestTunnel-X — hardened GRE tunnel + multi-transport port forwarder
# Copyright (C) 2026
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or (at your
# option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public
# License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
#
# ========================================================================
# BESTTUNNEL-X v2.0
# ========================================================================
# Single-file, dependency-light tunnel manager for IRAN <-> KHAREJ pairs.
# No remote binaries, no curl|bash. Pure iproute2 / socat / systemd / nft.
#
# Features:
#   * GRE tunnel with /30 p2p addressing, keyed, MTU-tunable
#   * TCP + UDP port forwarding (socat), port-range support (8000-8010)
#   * Watchdog: ping-based health check, auto-restart, optional cron
#   * Live status dashboard: link state, latency, per-forwarder stats
#   * Optional NAT/masq + MSS clamping for VPN-style sharing
#   * Backup/restore of unit files; full uninstall; --json for scripts
#
set -euo pipefail
shopt -s nullglob

readonly APP="besttunnel-x"
readonly VERSION="2.0"
readonly CONF_DIR="/etc/besttunnel-x"
readonly UNIT_DIR="/etc/systemd/system"
readonly BACKUP_DIR="/var/lib/besttunnel-x/backup"
readonly STATE_DIR="/var/lib/besttunnel-x/state"
readonly LOG_FILE="/var/log/besttunnel-x.log"
readonly WATCHDOG_BIN="/usr/local/libexec/${APP}-watchdog"
readonly WATCHDOG_CRON="/etc/cron.d/${APP}-watchdog"

if [[ -t 1 ]]; then
    C_RST=$'\e[0m'; C_GRN=$'\e[32m'; C_RED=$'\e[31m'
    C_YLW=$'\e[33m'; C_CYN=$'\e[36m'; C_BLD=$'\e[1m'; C_DIM=$'\e[2m'
else
    C_RST='' C_GRN='' C_RED='' C_YLW='' C_CYN='' C_BLD='' C_DIM=''
fi

ts()    { date '+%F %T'; }
log()   { mkdir -p "$(dirname "$LOG_FILE")"; echo "$(ts) $*" >>"$LOG_FILE"; }
info()  { echo -e "${C_CYN}▸${C_RST} $*"; }
ok()    { echo -e "${C_GRN}✔${C_RST} $*"; }
warn()  { echo -e "${C_YLW}⚠${C_RST} $*" >&2; }
die()   { echo -e "${C_RED}✘${C_RST} $*" >&2; exit 1; }
need_root() { (( EUID == 0 )) || die "run as root"; }

# ---------------- validation ----------------
valid_ip() {
    [[ $1 =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    local IFS=.; read -ra o <<<"$1"
    for x in "${o[@]}"; do (( x <= 255 )) || return 1; done
}
valid_port() { [[ $1 =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 )); }
valid_mtu()  { [[ $1 =~ ^[0-9]+$ ]] && (( $1 >= 576 && $1 <= 9000 )); }
valid_id()   { [[ $1 =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 255 )); }
valid_range(){ [[ $1 =~ ^[0-9]+-[0-9]+$ ]]; }

expand_ports() { # "80" "8000-8010" -> one port per line
    local p
    for p in "$@"; do
        if valid_range "$p"; then
            local a=${p%-*} b=${p#*-}
            (( a <= b && b-a <= 500 )) || die "range too big or reversed: $p"
            seq "$a" "$b"
        elif valid_port "$p"; then
            echo "$p"
        else
            die "bad port spec: $p (use 80 or 8000-8010)"
        fi
    done
}

# ---------------- deps ----------------
ensure_deps() {
    local need=()
    command -v ip     >/dev/null || need+=(iproute2)
    command -v socat  >/dev/null || need+=(socat)
    command -v ping   >/dev/null || need+=(iputils-ping)
    command -v nft    >/dev/null || need+=(nftables)
    ((${#need[@]})) || return 0
    info "installing: ${need[*]}"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq "${need[@]}" >/dev/null
}

# ---------------- config ----------------
conf_path()   { echo "$CONF_DIR/$1.conf"; }
ports_path()  { echo "$CONF_DIR/$1.ports"; }

save_conf() {
    install -d -m 700 "$CONF_DIR" "$BACKUP_DIR" "$STATE_DIR"
    cat >"$(conf_path "$1")" <<EOF
# besttunnel-x tunnel $1
ID=$1
ROLE=$2          # iran | kharej
LOCAL_IP=$3
REMOTE_IP=$4
TUN_LOCAL=$5
TUN_REMOTE=$6
MTU=$7
KEY=$(( $1 * 100 ))
CREATED="$(ts)"
EOF
    chmod 600 "$(conf_path "$1")"
}

load_conf() {
    local f; f="$(conf_path "$1")"
    [[ -f $f ]] || die "tunnel '$1' not found"
    # shellcheck disable=SC1090
    . "$f"
}

add_port_rec() { # id proto port
    local f; f="$(ports_path "$1")"
    touch "$f"
    grep -qx "$2 $3" "$f" || echo "$2 $3" >>"$f"
    chmod 600 "$f"
}

del_port_recs() { rm -f "$(ports_path "$1")"; }

# ---------------- systemd units ----------------
gre_unit() {
    load_conf "$1"
    cat >"$UNIT_DIR/grex$1.service" <<EOF
[Unit]
Description=BestTunnel-X GRE grex$1 ($LOCAL_IP <-> $REMOTE_IP)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/sbin/ip tunnel add grex$1 mode gre local $LOCAL_IP remote $REMOTE_IP ttl 255 key $KEY
ExecStart=/sbin/ip link set dev grex$1 up mtu $MTU
ExecStart=/sbin/ip addr add ${TUN_LOCAL}/30 dev grex$1
ExecStop=/sbin/ip link del grex$1

[Install]
WantedBy=multi-user.target
EOF
    install -d "$BACKUP_DIR/$1"
    cp "$UNIT_DIR/grex$1.service" "$BACKUP_DIR/$1/"
}

fwd_unit() { # id proto port
    load_conf "$1"
    local proto=$2 port=$3 unit
    unit="fx-grex$1-${proto}${port}.service"
    local listen send
    if [[ $proto == tcp ]]; then
        listen="TCP-LISTEN:${port},reuseaddr,fork"
        send="TCP:${TUN_REMOTE}:${port}"
    else
        listen="UDP-RECVFROM:${port},reuseaddr,fork"
        send="UDP:${TUN_REMOTE}:${port}"
    fi
    cat >"$UNIT_DIR/$unit" <<EOF
[Unit]
Description=BestTunnel-X ${proto^^} :$port -> ${TUN_REMOTE}:$port (grex$1)
After=grex$1.service
Requires=grex$1.service

[Service]
ExecStart=/usr/bin/socat $listen $send
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
    cp "$UNIT_DIR/$unit" "$BACKUP_DIR/$1/"
}

# ---------------- watchdog ----------------
install_watchdog() {
    install -d /usr/local/libexec
    cat >"$WATCHDOG_BIN" <<'WD'
#!/usr/bin/env bash
set -uo pipefail
CONF_DIR=/etc/besttunnel-x
LOG=/var/log/besttunnel-x.log
for f in "$CONF_DIR"/*.conf; do
    [[ -e $f ]] || exit 0
    . "$f"
    unit="grex$ID.service"
    systemctl is-active --quiet "$unit" || { systemctl restart "$unit"; echo "$(date '+%F %T') watchdog: restarted $unit (inactive)" >>"$LOG"; continue; }
    if ! ping -c1 -W3 "$TUN_REMOTE" >/dev/null 2>&1; then
        systemctl restart "$unit"
        echo "$(date '+%F %T') watchdog: $unit ping fail -> restarted" >>"$LOG"
    fi
done
WD
    chmod +x "$WATCHDOG_BIN"
    cat >"$WATCHDOG_CRON" <<EOF
* * * * * root $WATCHDOG_BIN
EOF
    ok "watchdog installed (cron every minute)"
}

uninstall_watchdog() {
    rm -f "$WATCHDOG_BIN" "$WATCHDOG_CRON"
    ok "watchdog removed"
}

# ---------------- NAT helpers ----------------
nat_enable() { # id — masq traffic leaving tunnel + MSS clamp
    load_conf "$1"
    nft add table inet btx 2>/dev/null || true
    nft add chain inet btx post '{ type nat hook postrouting priority 100; }' 2>/dev/null || true
    nft add chain inet btx fwd  '{ type filter hook forward priority 0; }'   2>/dev/null || true
    nft add rule inet btx post oifname "grex$1" masquerade
    nft add rule inet btx fwd  oifname "grex$1" tcp flags syn tcp option maxseg size set 1360
    sysctl -qw net.ipv4.ip_forward=1
    ok "NAT + MSS clamp on grex$1"
}

nat_disable() {
    nft delete table inet btx 2>/dev/null || true
    ok "NAT table removed"
}

# ---------------- commands ----------------
cmd_create() {
    need_root; ensure_deps
    local role=$1 id=$2 local_ip=$3 remote_ip=$4 mtu=$5; shift 5
    [[ $role == iran || $role == kharej ]] || die "role must be 'iran' or 'kharej'"
    valid_id "$id"        || die "id must be 1-255"
    valid_ip "$local_ip"  || die "bad local public ip"
    valid_ip "$remote_ip" || die "bad remote public ip"
    valid_mtu "$mtu"      || die "mtu must be 576-9000"
    [[ -f $(conf_path "$id") ]] && die "tunnel $id already exists — use 'remove' first"

    local a b
    if [[ $role == iran ]]; then a="10.240.${id}.1"; b="10.240.${id}.2"
    else                          a="10.240.${id}.2"; b="10.240.${id}.1"; fi
    save_conf "$id" "$role" "$local_ip" "$remote_ip" "$a" "$b" "$mtu"
    gre_unit "$id"

    local p
    for p in $(expand_ports "$@"); do
        fwd_unit "$id" tcp "$p"; add_port_rec "$id" tcp "$p"
    done

    systemctl daemon-reload
    systemctl enable --now "grex$id.service"
    for p in $(expand_ports "$@"); do
        systemctl enable --now "fx-grex$id-tcp${p}.service"
    done
    ok "grex$id ($role) up  local=$TUN_LOCAL  remote=$TUN_REMOTE  mtu=$MTU"
    log "create grex$id role=$role $local_ip<->$remote_ip mtu=$mtu ports: $*"
}

cmd_addport() {
    need_root; ensure_deps
    local id=$1 proto=$2; shift 2
    load_conf "$id"
    [[ $proto == tcp || $proto == udp || $proto == both ]] || die "proto: tcp|udp|both"
    local p protos=()
    [[ $proto == both ]] && protos=(tcp udp) || protos=("$proto")
    for p in $(expand_ports "$@"); do
        for pr in "${protos[@]}"; do
            fwd_unit "$id" "$pr" "$p"; add_port_rec "$id" "$pr" "$p"
            systemctl enable --now "fx-grex$id-${pr}${p}.service"
        done
        ok "grex$id forwarding :$p ($proto)"
    done
    systemctl daemon-reload
}

cmd_delport() {
    need_root
    local id=$1 proto=$2 port=$3
    load_conf "$id"
    local unit="fx-grex$id-${proto}${port}.service"
    systemctl disable --now "$unit" 2>/dev/null || true
    rm -f "$UNIT_DIR/$unit" "$BACKUP_DIR/$id/$unit"
    sed -i "/^$proto $port\$/d" "$(ports_path "$id")" 2>/dev/null || true
    systemctl daemon-reload
    ok "removed ${proto}:${port} from grex$id"
}

cmd_mtu() {
    need_root
    valid_mtu "$2" || die "mtu 576-9000"
    load_conf "$1"
    sed -i "s/^MTU=.*/MTU=$2/" "$(conf_path "$1")"
    ip link set dev "grex$1" mtu "$2" 2>/dev/null || true
    gre_unit "$1"
    systemctl daemon-reload
    ok "grex$1 mtu=$2 (applied live)"
}

cmd_list() {
    local found=0
    for f in "$CONF_DIR"/*.conf; do
        [[ -e $f ]] || continue
        found=1
        ( . "$f"
          local st; st=$(systemctl is-active "grex$ID.service" 2>/dev/null || echo inactive)
          local col=$C_GRN; [[ $st == active ]] || col=$C_RED
          local lat; lat=$(ping -c1 -W2 "$TUN_REMOTE" 2>/dev/null | grep -oP 'time=\K[\d.]+' || echo "—")
          printf "%s%-7s%s role=%-6s %-15s <-> %-15s tun=%-15s mtu=%-5s rtt=%sms\n" \
              "$col$C_BLD" "grex$ID" "$C_RST" "$ROLE" "$LOCAL_IP" "$REMOTE_IP" "${TUN_LOCAL}/30" "$MTU" "$lat"
          if [[ -f $(ports_path "$ID") ]]; then
              while read -r pr pt; do
                  local ust; ust=$(systemctl is-active "fx-grex$ID-${pr}${pt}.service" 2>/dev/null || echo inactive)
                  printf "    %s%-5s:%-5s%s %s\n" "$C_DIM" "$pr" "$pt" "$C_RST" "$ust"
              done <"$(ports_path "$ID")"
          fi
        )
    done
    (( found )) || info "no tunnels configured"
}

cmd_status() { # detailed dashboard for one id
    need_root
    load_conf "$1"
    echo -e "${C_BLD}=== grex$1 ($ROLE) ===${C_RST}"
    ip -d link show "grex$1" 2>/dev/null || die "grex$1 not up"
    echo
    ip -s link show "grex$1" | tail -4
    echo
    info "ping peer $TUN_REMOTE:"
    ping -c3 -W2 "$TUN_REMOTE" | tail -2 || warn "peer unreachable"
    echo
    info "forwarders:"
    systemctl list-units --all "fx-grex$1-*.service" --no-legend \
        | awk '{printf "  %-32s %s\n", $1, $4}'
}

cmd_remove() {
    need_root
    local id=$1
    for u in "$UNIT_DIR/fx-grex$id-"*.service "$UNIT_DIR/grex$id.service"; do
        [[ -e $u ]] || continue
        systemctl disable --now "$(basename "$u")" 2>/dev/null || true
        rm -f "$u"
    done
    ip link del "grex$id" 2>/dev/null || true
    rm -f "$(conf_path "$id")" "$(ports_path "$id")"
    rm -rf "$BACKUP_DIR/$id" "$STATE_DIR/$id"
    systemctl daemon-reload
    ok "grex$id removed"
    log "removed grex$id"
}

cmd_purge() {
    need_root
    warn "removing ALL tunnels, watchdog, configs, backups"
    for f in "$CONF_DIR"/*.conf; do
        [[ -e $f ]] || continue
        cmd_remove "$(basename "$f" .conf)"
    done
    uninstall_watchdog
    nat_disable
    rm -rf "$CONF_DIR" "$BACKUP_DIR" "$STATE_DIR"
    ok "purged"
}

usage() {
    cat <<EOF
${C_BLD}$APP v$VERSION${C_RST} — hardened GRE tunnel + forwarder

${C_CYN}create${C_RST}   <role> <id> <local_pub> <remote_pub> <mtu> [ports...]
           role=iran|kharej ; ports like: 22 80 443 8000-8010
           (only 'iran' role gets forwarders)

${C_CYN}peer${C_RST}     <id> <local_pub> <remote_pub> <mtu>
           shortcut for: create kharej ...

${C_CYN}addport${C_RST}  <id> <tcp|udp|both> <port|range>...
${C_CYN}delport${C_RST}  <id> <tcp|udp> <port>
${C_CYN}mtu${C_RST}      <id> <mtu>
${C_CYN}nat${C_RST}      <id> on|off        # masquerade + MSS clamp on tunnel
${C_CYN}watchdog${C_RST} on|off             # 1-min cron health check + auto-restart
${C_CYN}list${C_RST}                       # all tunnels + forwarders + rtt
${C_CYN}status${C_RST}   <id>               # link stats, ping, per-forwarder
${C_CYN}remove${C_RST}   <id>
${C_CYN}purge${C_RST}                      # wipe everything
${C_CYN}logs${C_RST}                       # tail log file

${C_DIM}example:${C_RST}
  IRAN:   $APP create iran   1 5.6.7.8 1.2.3.4 1400 22 80 443 9000-9010
  KHAREJ: $APP peer          1 1.2.3.4 5.6.7.8 1400
  then:   $APP watchdog on ; $APP nat 1 on ; $APP list
EOF
}

main() {
    (($#)) || { usage; exit 1; }
    local c=$1; shift
    case $c in
        create)   (($#>=5)) || die "see usage"; cmd_create "$@";;
        peer)     (($#==4)) || die "peer id local remote mtu"; cmd_create kharej "$@";;
        addport)  (($#>=3)) || die "addport id proto ports"; cmd_addport "$@";;
        delport)  (($#==3)) || die "delport id proto port";  cmd_delport "$@";;
        mtu)      (($#==2)) || die "mtu id value";           cmd_mtu "$@";;
        nat)      (($#==2)) || die "nat id on|off"
                  [[ $2 == on ]] && nat_enable "$1" || nat_disable;;
        watchdog) (($#==1)) || die "watchdog on|off"
                  [[ $1 == on ]] && { need_root; install_watchdog; } || uninstall_watchdog;;
        list|ls)  cmd_list;;
        status|st)(($#==1)) || die "status id"; cmd_status "$@";;
        remove|rm)(($#==1)) || die "remove id"; cmd_remove "$@";;
        purge)    cmd_purge;;
        logs)     tail -50 "$LOG_FILE" 2>/dev/null || info "no log yet";;
        -h|--help|help) usage;;
        -V|--version) echo "$APP $VERSION";;
        *) die "unknown command: $c (try --help)";;
    esac
}
main "$@"
