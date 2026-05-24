#!/usr/bin/env bash
# androidbox-watch — osserva le cartelle condivise host↔Android e, a OGNI
# modifica, triggera in automatico un rescan MediaStore (via il root helper
# /usr/libexec/androidbox-scan), così un file aggiunto SULL'HOST appare nella
# Galleria Android entro pochi secondi — niente comando manuale, niente restart.
#
# Perché serve: il bind-mount rende i file live sul FILESYSTEM, ma le scritture
# host-side bypassano l'inotify di Android → il MediaStore (quello che legge la
# Galleria) non le rileva da solo. androidbox-share fa uno scan UNA-TANTUM al
# bind; questo demone tiene lo scan SEMPRE allineato finché Android è attivo.
#
# Modello: legge la config ~/.config/androidbox/shares (righe HOSTDIR|SUBDIR), poi
# un singolo `inotifywait -m -r` su tutte le HOSTDIR esistenti; ogni evento viene
# rimappato dalla sua HOSTDIR alla ANDROID_SUBDIR e DEBOUNCED (trailing-edge: un
# burst di modifiche = 1 solo scan, lanciato dopo ~2s di quiete sulla subdir)
# prima di chiamare `sudo androidbox-scan <SUBDIR>`.
#
# Gestito come USER unit (androidbox-watch.service), abilitata/disabilitata dal
# lifecycle di androidbox-start/androidbox-stop. Esecuzione diretta ok per debug.
set -uo pipefail

# mise-immune: /usr/bin davanti così waydroid (shebang `env python3`) e gli altri
# tool usano il python/binari di SISTEMA, non quelli eventuali di mise.
export PATH="/usr/bin:$PATH"

CFG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/androidbox"
CFG="$CFG_DIR/shares"
SCAN=/usr/libexec/androidbox-scan
DEBOUNCE_SECS=2        # quiete richiesta prima dello scan (trailing-edge debounce)

say()  { printf '\033[1;36m▶\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[33m!\033[0m %s\n' "$*" >&2; }

# ── Prerequisiti gestiti con grazia ─────────────────────────────────────────
if ! command -v inotifywait >/dev/null; then
    warn "inotifywait non installato (pacchetto inotify-tools): impossibile osservare. Esco."
    exit 0   # exit pulito: niente Restart-loop sulla user unit per una dep mancante.
fi
if [ ! -f "$CFG" ]; then
    warn "Nessuna config condivisioni ($CFG): niente da osservare. Esco."
    exit 0
fi

# ── Costruisci: lista HOSTDIR da osservare + mappa HOSTDIR→SUBDIR ────────────
# read_mappings: righe valide HOSTDIR|SUBDIR (commenti/vuote escluse).
declare -a HOSTDIRS=()
declare -A SUB_OF=()    # HOSTDIR(assoluto, no slash finale) → SUBDIR
while IFS='|' read -r host sub; do
    # salta commenti/vuote
    case "$host" in ''|'#'*) continue;; esac
    [ -n "${sub:-}" ] || continue
    host="${host%/}"               # normalizza: niente slash finale
    if [ -d "$host" ]; then
        HOSTDIRS+=("$host")
        SUB_OF["$host"]="$sub"
    else
        warn "host dir assente, salto: $host"
    fi
done < <(grep -vE '^[[:space:]]*(#|$)' "$CFG" 2>/dev/null || true)

if [ "${#HOSTDIRS[@]}" -eq 0 ]; then
    warn "Nessuna cartella host esistente da osservare. Esco."
    exit 0
fi

# Risolvi la SUBDIR di un path di evento risalendo l'albero delle HOSTDIR.
# inotifywait -r emette %w = directory dell'evento (può essere una sottocartella
# annidata): mappiamo al longest-prefix tra le HOSTDIR osservate.
subdir_for_path() {
    local p="$1" h best=""
    p="${p%/}"
    for h in "${HOSTDIRS[@]}"; do
        case "$p/" in
            "$h"/*|"$h"/)
                # prendi il prefisso più lungo (gestisce HOSTDIR annidate)
                if [ "${#h}" -gt "${#best}" ]; then best="$h"; fi
                ;;
        esac
    done
    [ -n "$best" ] && printf '%s\n' "${SUB_OF[$best]}"
}

say "Osservo ${#HOSTDIRS[@]} cartella/e condivisa/e; debounce ${DEBOUNCE_SECS}s per subdir."
for h in "${HOSTDIRS[@]}"; do ok "watch: $h → /storage/emulated/0/${SUB_OF[$h]}"; done

# ── Debounce per-subdir (trailing-edge, no event perso) ─────────────────────
# Coalescenza: gli eventi marcano una subdir come "pending"; lo scan parte solo
# DOPO che la subdir è rimasta QUIETA per DEBOUNCE_SECS. Così un burst di N file
# = 1 solo scan, ma eseguito QUANDO il burst è finito (lo scan_file ricorsivo
# vede tutti i file presenti a quel punto) → nessun file aggiunto a fine burst
# resta fuori. Implementazione senza timer asincroni: il `read -t` del loop fa da
# tick; allo scadere del timeout (= quiete) facciamo il flush delle pending.
declare -A PENDING=()      # SUBDIR → 1 se ha eventi non ancora scansionati

flush_pending() {
    local sub
    for sub in "${!PENDING[@]}"; do
        unset 'PENDING[$sub]'
        if sudo -n "$SCAN" "$sub" >/dev/null 2>&1; then
            ok "rescan MediaStore: /storage/emulated/0/$sub"
        else
            warn "rescan fallito per $sub (Android giù? regola sudoers assente?)"
        fi
    done
}

# ── Loop principale: un solo inotifywait -m -r su tutte le HOSTDIR ───────────
# Eventi: close_write (file scritto), create/moved_to (aggiunto), move/delete
# (così anche le rimozioni aggiornano la Galleria). Formato '%w|%f' = dir|file.
# `read -t DEBOUNCE_SECS`: se entro la finestra non arrivano altri eventi, il
# read va in timeout (exit >128) → flush delle subdir pending (trailing-edge).
inotifywait -m -r \
    -e close_write -e create -e moved_to -e move -e delete \
    --format '%w|%f' \
    "${HOSTDIRS[@]}" 2>/dev/null |
while true; do
    if IFS='|' read -r -t "$DEBOUNCE_SECS" evdir _evfile; then
        # evento ricevuto: marca la subdir come pending (coalescenza nel burst)
        [ -n "$evdir" ] || continue
        sub="$(subdir_for_path "$evdir")" || continue
        [ -n "$sub" ] || continue
        PENDING["$sub"]=1
    else
        rc=$?
        # rc>128 = timeout di read (quiete): flush. rc>0 e ≤128 = EOF/pipe chiusa
        # (inotifywait morto) → flush residui ed esci così la unit riavvia.
        flush_pending
        [ "$rc" -gt 128 ] || break
    fi
done
