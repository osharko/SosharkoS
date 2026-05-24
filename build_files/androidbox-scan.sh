#!/usr/bin/env bash
# androidbox-scan — root helper: forza un rescan MediaStore di UNA subdir Android.
#
# Pensato per essere invocato via sudo da androidbox-watch (utente non-root):
#   sudo /usr/libexec/androidbox-scan <SUBDIR>
# Una regola sudoers stretta (/etc/sudoers.d/androidbox-scan) concede il NOPASSWD
# SOLO su questo binario, NON su `waydroid`/`waydroid shell` in generale. Per
# tenere quella regola SICURA, l'unico argomento (la subdir Android) è validato
# in modo RIGIDO: solo [A-Za-z0-9_], qualsiasi altra cosa → exit non-zero. Così
# l'utente non può iniettare path arbitrari né flag aggiuntive in `waydroid shell`.
#
# Perché serve root: `waydroid shell` rifiuta l'invocazione non-root; il rescan
# (`content call ... scan_file`) gira nella shell del container e richiede root.
# I file scritti host-side via bind-mount bypassano l'inotify di Android → senza
# questo scan esplicito la Galleria/MediaStore non li vede finché non si riavvia.
set -euo pipefail

# mise-immune: PATH pulito di sistema. Invocato via sudo eredita comunque il PATH
# pulito di root, ma lo forziamo per difesa in profondità (es. esecuzione diretta).
export PATH=/usr/bin

SUB="${1:-}"

# Validazione RIGIDA dell'unico argomento: solo lettere/cifre/underscore.
# Niente '/', '.', '-', spazi, '..' ecc. → impossibile uscire da
# /storage/emulated/0/<SUB> o passare flag a waydroid/content.
case "$SUB" in
    "" )
        printf 'androidbox-scan: subdir mancante\n' >&2
        exit 2
        ;;
    *[!A-Za-z0-9_]* )
        printf 'androidbox-scan: subdir non valida (ammessi solo [A-Za-z0-9_]): %s\n' "$SUB" >&2
        exit 2
        ;;
esac

# Rescan ricorsivo della subdir montata. Best-effort: se Android non è su o la
# shell non risponde, esce non-zero e il chiamante (watch) lo ignora.
exec waydroid shell -- content call \
    --uri content://media \
    --method scan_file \
    --arg "/storage/emulated/0/$SUB"
