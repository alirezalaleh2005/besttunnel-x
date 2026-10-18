#!/usr/bin/env bash
#
# BestTunnel-X — one-liner installer (local or remote)
#
# Two modes:
#
#   A) Local install — when install.sh sits next to besttunnel-x.sh:
#        sudo bash install.sh
#
#   B) Remote install — single command, downloads latest from GitHub:
#        bash <(curl -fsSL https://raw.githubusercontent.com/<USER>/<REPO>/main/install.sh)
#        # or
#        curl -fsSL https://raw.githubusercontent.com/<USER>/<REPO>/main/install.sh | sudo bash
#
set -euo pipefail

REPO_RAW="${BTX_REPO_RAW:-https://raw.githubusercontent.com/alirezalaleh2005/BestTunnel-X/main}"
DEST="${BTX_DEST:-/usr/local/bin/btx}"

c_red=$'\e[31m'; c_grn=$'\e[32m'; c_cyn=$'\e[36m'; c_yel=$'\e[33m'; c_rst=$'\e[0m'
info() { echo -e "${c_cyn}▸${c_rst} $*"; }
ok()   { echo -e "${c_grn}✔${c_rst} $*"; }
warn() { echo -e "${c_yel}⚠${c_rst} $*"; }
die()  { echo -e "${c_red}✘${c_rst} $*" >&2; exit 1; }

(( EUID == 0 )) || die "run as root (or use sudo)"

# ── resolve source script ────────────────────────────────────────────
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")"
LOCAL_SRC=""
[[ -n $SRC_DIR && -f "$SRC_DIR/besttunnel-x.sh" ]] && LOCAL_SRC="$SRC_DIR/besttunnel-x.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

if [[ -n $LOCAL_SRC ]]; then
    info "found local besttunnel-x.sh — installing from disk"
    cp "$LOCAL_SRC" "$TMP/btx"
else
    info "no local file — downloading from GitHub"
    info "repo: $REPO_RAW"
    if command -v curl >/dev/null; then
        curl -fsSL "$REPO_RAW/besttunnel-x.sh" -o "$TMP/btx" \
            || die "download failed — check URL / network"
    elif command -v wget >/dev/null; then
        wget -qO "$TMP/btx" "$REPO_RAW/besttunnel-x.sh" \
            || die "download failed — check URL / network"
    else
        die "need curl or wget to download"
    fi
fi

# sanity checks
[[ -s $TMP/btx ]] || die "empty file"
head -1 "$TMP/btx" | grep -q '^#!/usr/bin/env bash' || die "not a bash script"
grep -q 'BESTTUNNEL-X'    "$TMP/btx" || die "missing BESTTUNNEL-X marker"
grep -q 'cmd_create()'    "$TMP/btx" || die "missing cmd_create — corrupt file"
bash -n "$TMP/btx"                     || die "syntax error in downloaded file"
ok "script verified"

# install
install -m 755 "$TMP/btx" "$DEST"
ok "installed → $DEST"

# optional: license + readme next to it
if [[ -n $LOCAL_SRC ]]; then
    [[ -f $SRC_DIR/LICENSE ]]   && install -m 644 "$SRC_DIR/LICENSE"   /usr/local/share/besttunnel-x.LICENSE   2>/dev/null || true
    [[ -f $SRC_DIR/README.md ]] && install -m 644 "$SRC_DIR/README.md" /usr/local/share/besttunnel-x.README.md 2>/dev/null || true
else
    curl -fsSL "$REPO_RAW/LICENSE"   -o /usr/local/share/besttunnel-x.LICENSE   2>/dev/null || true
    curl -fsSL "$REPO_RAW/README.md" -o /usr/local/share/besttunnel-x.README.md 2>/dev/null || true
fi

# ensure runtime deps (quiet — non-fatal)
need=()
command -v ip    >/dev/null || need+=(iproute2)
command -v socat >/dev/null || need+=(socat)
command -v ping  >/dev/null || need+=(iputils-ping)
if ((${#need[@]})); then
    info "installing deps: ${need[*]}"
    if command -v apt-get >/dev/null; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq && apt-get install -y -qq "${need[@]}" >/dev/null \
            && ok "deps installed" \
            || warn "dep install failed — install manually: ${need[*]}"
    else
        warn "non-apt system — install manually: ${need[*]}"
    fi
fi

echo
ok "done"
echo "  binary : $DEST"
echo "  help   : btx --help"
echo "  docs   : less /usr/local/share/besttunnel-x.README.md"
echo
