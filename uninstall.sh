#!/usr/bin/env bash
# Removes btx and all tunnels created by it.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run as root"; exit 1; }

if command -v btx >/dev/null; then
    btx purge || true
fi
rm -f /usr/local/bin/btx
rm -rf /etc/besttunnel-x /var/lib/besttunnel-x
rm -f /var/log/besttunnel-x.log /usr/local/libexec/besttunnel-x-watchdog /etc/cron.d/besttunnel-x-watchdog
echo "✔ besttunnel-x removed"
