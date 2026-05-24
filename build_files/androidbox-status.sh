#!/usr/bin/env bash
# androidbox-status — riepiloga lo stato dell'UX Android (Waydroid):
#   - `waydroid status`
#   - is-enabled / is-active di waydroid-container.service (SYSTEM)
#   - is-enabled / is-active di waydroid-session.service   (USER)
#   - inizializzato sì/no (presenza di system.img)
# Sola lettura, idempotente, nessun privilegio richiesto.
set -uo pipefail

SYS_UNIT=waydroid-container.service
USR_UNIT=waydroid-session.service
SYSIMG=/var/lib/waydroid/images/system.img

hdr() { printf '\n\033[1m%s\033[0m\n' "$*"; }
kv()  { printf '  %-18s %s\n' "$1" "$2"; }

hdr "waydroid status"
if command -v waydroid >/dev/null; then
    waydroid status 2>/dev/null | sed 's/^/  /' || echo "  (impossibile interrogare waydroid)"
else
    echo "  waydroid non installato"
fi

hdr "Unit systemd"
kv "container (sys):" "enabled=$(systemctl is-enabled "$SYS_UNIT" 2>/dev/null || echo n/a)  active=$(systemctl is-active "$SYS_UNIT" 2>/dev/null || echo n/a)"
kv "session (user):"  "enabled=$(systemctl --user is-enabled "$USR_UNIT" 2>/dev/null || echo n/a)  active=$(systemctl --user is-active "$USR_UNIT" 2>/dev/null || echo n/a)"

hdr "Inizializzazione"
if [ -f "$SYSIMG" ]; then
    kv "initialized:" "sì ($SYSIMG presente)"
else
    kv "initialized:" "no — il primo 'androidbox-start' eseguirà 'waydroid init -s GAPPS'"
fi
echo
