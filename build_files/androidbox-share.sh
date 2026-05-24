#!/usr/bin/env bash
# androidbox-share / androidbox-unshare — condividi cartelle HOST con Android
# (Waydroid) via bind-mount, così gli STESSI file appaiono sull'host e dentro
# Android (la Galleria vede ~/Immagini, ecc.).
#
# Modello "config-driven + lifecycle-bound" (reversibile, sopravvive ai reboot,
# resiste agli upgrade di waydroid — NON tocca la config LXC né usa .mount unit
# fragili per-path):
#   - Un file di config  ~/.config/androidbox/shares  con righe  HOSTDIR|SUBDIR
#     (es.  /home/u/Immagini|Pictures).
#   - I bind veri vengono (ri)applicati ad ogni `androidbox-start` leggendo la
#     config; `androidbox-stop` li smonta tutti. Questo script gestisce la config
#     e applica/smonta SUBITO quando Android è attivo.
#
# USO:
#   androidbox-share                       # popola la config con i DEFAULT presi
#                                          # dai tuoi XDG dir e li applica subito
#   androidbox-share <hostdir> [subdir]    # aggiunge un mapping (subdir default =
#                                          # basename) + applica subito
#   androidbox-share --list                # mostra i mapping + stato mount
#   androidbox-unshare <hostdir>           # rimuove un mapping + smonta
#   androidbox-unshare --all               # rimuove TUTTO + smonta tutto
#
# Il bind avviene su  <DATADIR>/media/0/<SUBDIR>  (l'/sdcard di Android), dove
# DATADIR è rilevato dinamicamente (user-mode vs system-mode, vedi sotto). Dopo
# il bind forza un rescan MediaStore SENZA riavviare Android, così la Galleria/
# file manager indicizzano i file subito (i file scritti host-side bypassano
# l'inotify di Android → serve uno scan esplicito).
set -uo pipefail

# mise-immune: /usr/bin davanti, così lo shebang `env python3` di waydroid usa il
# python di SISTEMA (con i binding dbus) e non quello eventuale di mise.
export PATH="/usr/bin:$PATH"

CFG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/androidbox"
CFG="$CFG_DIR/shares"

say()  { printf '\033[1;36m▶\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[33m!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# ── Rileva la DATADIR di Waydroid (mode-dependent) ──────────────────────────
# user-mode  → ~/.local/share/waydroid/data   (questo host)
# system-mode→ /var/lib/waydroid/data         (probabile nell'immagine)
# Si usa quella il cui  .../media/0  esiste davvero (= Android inizializzato).
datadir() {
    local u="$HOME/.local/share/waydroid/data" s="/var/lib/waydroid/data"
    if   sudo test -d "$u/media/0"; then printf '%s\n' "$u"
    elif sudo test -d "$s/media/0"; then printf '%s\n' "$s"
    else return 1; fi
}

# sdcard root host-side (il /storage/emulated/0 di Android è qui sotto):
mediaroot() { local d; d="$(datadir)" || return 1; printf '%s/media/0\n' "$d"; }

# Android è in piedi? (sessione o container) — serve per applicare i bind subito.
android_up() {
    waydroid status 2>/dev/null | grep -qiE 'Session:[[:space:]]*RUNNING|Container:[[:space:]]*(RUNNING|FROZEN)'
}

# Normalizza un path host (assoluto, senza slash finale).
abspath() {
    local p="$1"
    case "$p" in
        "~"|"~/"*) p="$HOME${p#\~}";;
    esac
    [ -d "$p" ] && p="$(cd "$p" && pwd -P)" || p="${p%/}"
    printf '%s\n' "$p"
}

ensure_cfg() { mkdir -p "$CFG_DIR"; [ -f "$CFG" ] || : > "$CFG"; }

# Tutti i mapping validi della config → "HOSTDIR|SUBDIR" (commenti/vuote escluse).
read_mappings() {
    [ -f "$CFG" ] || return 0
    grep -vE '^[[:space:]]*(#|$)' "$CFG" || true
}

# Esiste già un mapping per questo HOSTDIR?
has_host() {
    local h="$1"
    read_mappings | cut -d'|' -f1 | grep -qxF "$h"
}

# Aggiunge/aggiorna un mapping nella config (HOSTDIR|SUBDIR), idempotente.
cfg_add() {
    local h="$1" s="$2"
    ensure_cfg
    # rimuovi eventuale riga preesistente per lo stesso HOSTDIR, poi append
    local tmp; tmp="$(mktemp)"
    grep -vE "^${h//\//\\/}\|" "$CFG" 2>/dev/null > "$tmp" || true
    printf '%s|%s\n' "$h" "$s" >> "$tmp"
    mv "$tmp" "$CFG"
}

# Rimuove un mapping dalla config.
cfg_del() {
    local h="$1" tmp
    [ -f "$CFG" ] || return 0
    tmp="$(mktemp)"
    grep -vE "^${h//\//\\/}\|" "$CFG" 2>/dev/null > "$tmp" || true
    mv "$tmp" "$CFG"
}

# È montato (bind attivo) su questo target?
is_mounted() { mountpoint -q "$1" 2>/dev/null || sudo mountpoint -q "$1" 2>/dev/null; }

# ── Applica un bind: HOSTDIR → <mediaroot>/SUBDIR (root), poi rescan ─────────
apply_bind() {
    local host="$1" sub="$2" mr tgt
    mr="$(mediaroot)" || { warn "Android non inizializzato: bind rimandato al prossimo androidbox-start."; return 1; }
    [ -d "$host" ] || { warn "host dir assente, salto: $host"; return 1; }
    tgt="$mr/$sub"
    # crea il target se manca (con permessi media: gid 1023/media_rw)
    if ! sudo test -d "$tgt"; then
        sudo mkdir -p "$tgt" && sudo chown 1023:1023 "$tgt" 2>/dev/null || true
    fi
    if is_mounted "$tgt"; then
        ok "già montato: $host → /storage/emulated/0/$sub"
        return 0
    fi
    if sudo mount --bind "$host" "$tgt"; then
        ok "bind: $host → /storage/emulated/0/$sub"
        rescan "$sub"
        return 0
    fi
    warn "bind fallito: $host → $tgt"
    return 1
}

# ── Smonta un bind (robusto: lazy fallback) ─────────────────────────────────
teardown_bind() {
    local sub="$1" mr tgt
    mr="$(mediaroot)" || return 0
    tgt="$mr/$sub"
    is_mounted "$tgt" || { return 0; }
    if sudo umount "$tgt" 2>/dev/null; then
        ok "smontato: /storage/emulated/0/$sub"
    elif sudo umount -l "$tgt" 2>/dev/null; then
        ok "smontato (lazy): /storage/emulated/0/$sub"
    else
        warn "umount fallito: $tgt (occupato?)"
        return 1
    fi
}

# ── Rescan MediaStore SENZA riavviare Android (VERIFICATO) ──────────────────
# Forza l'MediaProvider a (re)indicizzare la sottocartella appena montata.
rescan() {
    local sub="$1"
    android_up || return 0
    # scan ricorsivo della cartella; best-effort, non blocca.
    sudo waydroid shell -- content call --uri content://media --method scan_file \
        --arg "/storage/emulated/0/$sub" >/dev/null 2>&1 \
        && ok "rescan MediaStore: /storage/emulated/0/$sub" \
        || warn "rescan non riuscito per $sub (riprova ad Android avviato)."
}

# ── Default dai dir XDG (~/.config/user-dirs.dirs) ──────────────────────────
# Mappa: XDG_PICTURES→Pictures, XDG_DOWNLOAD→Download, XDG_MUSIC→Music,
#        XDG_DOCUMENTS→Documents, XDG_VIDEOS→Movies. Solo dir esistenti.
populate_defaults() {
    local ud="${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs"
    # source difensivo: leggi solo le var XDG_*_DIR
    local XDG_PICTURES_DIR XDG_DOWNLOAD_DIR XDG_MUSIC_DIR XDG_DOCUMENTS_DIR XDG_VIDEOS_DIR
    if [ -f "$ud" ]; then
        # shellcheck disable=SC1090
        . "$ud" 2>/dev/null || true
    fi
    # fallback ai nomi inglesi classici se le var non sono settate
    : "${XDG_PICTURES_DIR:=$HOME/Pictures}"
    : "${XDG_DOWNLOAD_DIR:=$HOME/Downloads}"
    : "${XDG_MUSIC_DIR:=$HOME/Music}"
    : "${XDG_DOCUMENTS_DIR:=$HOME/Documents}"
    : "${XDG_VIDEOS_DIR:=$HOME/Videos}"

    local added=0
    # subdir Android standard (quelle che la Galleria/file manager si aspettano)
    local pairs=(
        "$XDG_PICTURES_DIR|Pictures"
        "$XDG_DOWNLOAD_DIR|Download"
        "$XDG_MUSIC_DIR|Music"
        "$XDG_DOCUMENTS_DIR|Documents"
        "$XDG_VIDEOS_DIR|Movies"
    )
    local pair host sub
    for pair in "${pairs[@]}"; do
        host="${pair%%|*}"; sub="${pair##*|}"
        host="$(abspath "$host")"
        if [ -d "$host" ]; then
            cfg_add "$host" "$sub"
            ok "default: $host → /storage/emulated/0/$sub"
            added=$((added+1))
        else
            warn "salto default (dir assente): $host"
        fi
    done
    [ "$added" -gt 0 ] || warn "nessun XDG dir trovato → config vuota."
    return 0
}

# ── Applica TUTTI i mapping della config (usato da androidbox-start) ─────────
apply_all() {
    local any=0 line host sub
    while IFS='|' read -r host sub; do
        [ -n "$host" ] || continue
        apply_bind "$host" "$sub" && any=1
    done < <(read_mappings)
    [ "$any" = 1 ] || warn "nessun bind applicato (config vuota o Android non pronto)."
}

# ── Smonta TUTTI i mapping della config (usato da androidbox-stop) ───────────
teardown_all() {
    local host sub
    while IFS='|' read -r host sub; do
        [ -n "$sub" ] || continue
        teardown_bind "$sub"
    done < <(read_mappings)
}

# ── --list: mapping + stato mount ───────────────────────────────────────────
do_list() {
    printf '\033[1mandroidbox — cartelle condivise con Android\033[0m\n'
    printf '  config: %s\n\n' "$CFG"
    local mr; mr="$(mediaroot 2>/dev/null || true)"
    if [ -z "$(read_mappings)" ]; then
        echo "  (nessun mapping) — esegui 'androidbox-share' per i default."
        return 0
    fi
    printf '  %-34s %-14s %s\n' "HOST" "ANDROID" "MOUNT"
    local host sub tgt st
    while IFS='|' read -r host sub; do
        [ -n "$host" ] || continue
        tgt="${mr:+$mr/$sub}"
        if [ -n "$tgt" ] && is_mounted "$tgt"; then st="$(printf '\033[32mattivo\033[0m')"; else st="$(printf '\033[33mnon montato\033[0m')"; fi
        printf '  %-34s /sdcard/%-6s %b\n' "$host" "$sub" "$st"
    done < <(read_mappings)
}

usage() {
    sed -n '2,38p' "$0" | sed 's/^# \{0,1\}//'
}

# ════════════════════════════════════════════════════════════════════════════
# Dispatcher — il comportamento dipende dal nome con cui è invocato:
#   androidbox-share   → aggiunge/applica
#   androidbox-unshare → rimuove/smonta
# Argomenti speciali interni (usati da start/stop): --apply-all / --teardown-all
# ════════════════════════════════════════════════════════════════════════════
PROG="$(basename "$0")"

case "${1:-}" in
    --apply-all)    apply_all; exit 0;;
    --teardown-all) teardown_all; exit 0;;
    -h|--help|help) usage; exit 0;;
esac

command -v waydroid >/dev/null || die "waydroid non installato (atteso nell'immagine)."

if [ "$PROG" = "androidbox-unshare" ]; then
    # ── UNSHARE ─────────────────────────────────────────────────────────────
    case "${1:-}" in
        ""|--all)
            say "Rimuovo TUTTE le condivisioni e smonto i bind."
            teardown_all
            : > "$CFG" 2>/dev/null || true
            ok "Tutte le condivisioni rimosse. (le cartelle host sono INTATTE)"
            ;;
        --list) do_list;;
        *)
            host="$(abspath "$1")"
            if ! has_host "$host"; then warn "nessun mapping per: $host"; fi
            # trova la subdir associata per smontare
            sub="$(read_mappings | awk -F'|' -v h="$host" '$1==h{print $2; exit}')"
            [ -n "${sub:-}" ] && teardown_bind "$sub"
            cfg_del "$host"
            ok "rimosso mapping: $host (cartella host INTATTA)"
            ;;
    esac
    exit 0
fi

# ── SHARE ───────────────────────────────────────────────────────────────────
case "${1:-}" in
    --list|-l) do_list; exit 0;;
    "")
        say "Popolo la config con i default dai tuoi XDG dir."
        populate_defaults
        if android_up; then
            say "Android attivo → applico i bind ora."
            apply_all
        else
            warn "Android non attivo: i bind verranno applicati al prossimo 'androidbox-start'."
        fi
        echo
        do_list
        ;;
    *)
        host="$(abspath "$1")"
        [ -d "$host" ] || die "host dir inesistente: $host"
        sub="${2:-$(basename "$host")}"
        cfg_add "$host" "$sub"
        ok "mapping aggiunto: $host → /storage/emulated/0/$sub"
        if android_up; then
            apply_bind "$host" "$sub"
        else
            warn "Android non attivo: il bind verrà applicato al prossimo 'androidbox-start'."
        fi
        ;;
esac
