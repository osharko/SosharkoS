#!/usr/bin/env bash
# Primo boot: aggiunge Flathub (system-wide) e installa le app in flatpaks.list.
# Idempotente; il servizio gira una sola volta grazie al marker.
set -euo pipefail

LIST=/usr/share/sosharkos/flatpaks.list
MARKER=/var/lib/sosharkos/flatpaks-installed

flatpak remote-add --if-not-exists flathub \
    https://flathub.org/repo/flathub.flatpakrepo

# Installa ogni app-id non commentata, saltando quelle già presenti.
grep -vE '^\s*(#|$)' "$LIST" | while read -r app; do
    flatpak info "$app" >/dev/null 2>&1 && continue
    flatpak install -y --noninteractive flathub "$app" || \
        echo "WARN: install fallita per $app" >&2
done

mkdir -p "$(dirname "$MARKER")"
touch "$MARKER"
