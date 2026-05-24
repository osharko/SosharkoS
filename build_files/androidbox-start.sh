#!/usr/bin/env bash
# androidbox-start — accende l'UX Android (Waydroid) e la rende PERSISTENTE.
#
# Modello "opt-in che persiste": dopo `androidbox-start` Android torna a OGNI
# boot/login finché non esegui `androidbox-stop`. La persistenza è ottenuta con
# systemd enable (NON solo start):
#   - waydroid-container.service (SYSTEM) → enable --now  (parte al boot)
#   - waydroid-session.service   (USER)   → enable --now  (parte al login grafico)
#
# Nell'immagine il container service è installato ma DISABILITATO di default:
# zero consumo di risorse finché non opti-in qui.
#
# Idempotente: rieseguirlo è sicuro. Richiede rete SOLO al primissimo uso
# (waydroid init scarica ~1GB di immagini Android in /var).
set -euo pipefail

# mise-immune: /usr/bin davanti, così lo shebang `env python3` di waydroid usa il
# python di SISTEMA (con i binding dbus) e non quello eventuale di mise.
export PATH="/usr/bin:$PATH"

SYS_UNIT=waydroid-container.service
USR_UNIT=waydroid-session.service
SYSIMG=/var/lib/waydroid/images/system.img

say()  { printf '\033[1;36m▶\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[33m!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# ── Sanity: binderfs presente? (kernel CachyOS: binder è built-in =y) ──────
if [ ! -e /dev/binderfs ] && [ ! -e /dev/binder ]; then
    warn "Nessun /dev/binderfs né /dev/binder: il container potrebbe non avviarsi."
    warn "Atteso: kernel con CONFIG_ANDROID_BINDERFS=y (CachyOS COPR lo ha). Se"
    warn "manca, il pacchetto monta dev-binderfs.mount all'avvio del container;"
    warn "verifica con: systemctl status dev-binderfs.mount"
fi

command -v waydroid >/dev/null || die "waydroid non installato (atteso nell'immagine)."

# ── 1. Init one-time (se non inizializzato) ────────────────────────────────
# Rileva l'init tramite l'immagine system.img scritta da `waydroid init`.
if [ ! -f "$SYSIMG" ]; then
    say "Waydroid non inizializzato → eseguo l'init (UNA TANTUM)."
    say "Scarico le immagini Android system+vendor con Google Apps (GAPPS)."
    say "È un download ~1GB in /var e richiede CONNESSIONE DI RETE. Attendi…"
    sudo waydroid init -s GAPPS || die "waydroid init fallito (rete? spazio in /var?)."
    ok "Init completato (GAPPS)."
else
    ok "Waydroid già inizializzato."
fi

# ── 2. Container di sistema: enable + start (persiste al boot) ──────────────
say "Abilito e avvio $SYS_UNIT (parte a ogni boot)."
sudo systemctl enable --now "$SYS_UNIT" || die "impossibile abilitare/avviare $SYS_UNIT."

# ── 3. Attendo che il container sia su, poi sessione utente ─────────────────
say "Attendo che il container Android sia pronto…"
up=0
for _ in $(seq 1 30); do
    if waydroid status 2>/dev/null | grep -qiE 'session:|container.*RUNNING|RUNNING'; then up=1; break; fi
    # Anche il solo container RUNNING basta per avviare la sessione utente.
    if systemctl is-active --quiet "$SYS_UNIT"; then up=1; break; fi
    sleep 1
done
[ "$up" = 1 ] && ok "Container attivo." || warn "Container non confermato attivo: procedo comunque."

say "Abilito e avvio la sessione utente $USR_UNIT (parte al login grafico)."
systemctl --user enable --now "$USR_UNIT" \
    || warn "enable --now $USR_UNIT non riuscito (sessione grafica assente? riprova dopo il login)."

# ── 4. Proprietà Waydroid (best-effort, una volta che il container è su) ────
# multi_windows: ogni app Android in una finestra host dedicata (no UI unica).
# gralloc gbm: hint consigliato su AMD/mesa per il rendering accelerato (questo
#   host è AMD Radeon). Difensivo: se non serve, non fa danno.
if waydroid prop set persist.waydroid.multi_windows true 2>/dev/null; then
    ok "persist.waydroid.multi_windows = true (ogni app in finestra propria)."
else
    warn "Non ho potuto impostare multi_windows ora; riprova dopo il primo avvio:"
    warn "  waydroid prop set persist.waydroid.multi_windows true"
fi
waydroid prop set persist.waydroid.gralloc gbm 2>/dev/null \
    && ok "persist.waydroid.gralloc = gbm (hint AMD/mesa)." || true

# ── 5. Cartelle condivise host↔Android (bind-mount, §16) ────────────────────
# Best-effort + idempotente: se non c'è una config, no-op. I bind sono legati al
# lifecycle (li ri-applichiamo a OGNI start, li smonta androidbox-stop) → niente
# .mount unit fragili né modifiche alla config LXC (che si resetta agli upgrade).
say "Ri-applico le cartelle condivise (se configurate)…"
if command -v androidbox-share >/dev/null; then
    androidbox-share --apply-all 2>/dev/null \
        && ok "Cartelle condivise applicate (vedi: androidbox-share --list)." \
        || warn "Nessuna condivisione applicata (config vuota? Android non pronto?)."
else
    warn "androidbox-share non trovato: salto le cartelle condivise."
fi

cat <<'EOF'

──────────────────────────────────────────────────────────────────────────
Android UX (androidbox) ATTIVO e PERSISTENTE (tornerà a ogni boot/login).

Come avviare le app:
  • Dal launcher del desktop: le app Android esportano launcher .desktop
    propri (compaiono tra le applicazioni una volta installate/avviate).
  • Da terminale:   waydroid app list           # elenca le app
                    waydroid app launch <id>     # avvia una app
                    waydroid show-full-ui        # l'intera UI Android

Play Store (GAPPS) — CERTIFICAZIONE richiesta la prima volta, altrimenti dice
"Device not certified". Recupera l'android_id e registralo:
  sudo waydroid shell -- sh -c 'ANDROID_RUNTIME_ROOT=/apex/com.android.runtime \
    sqlite3 /data/data/com.google.android.gsf/databases/gservices.db \
    "select * from main where name = \"android_id\";"'
  → registra il valore su  https://www.google.com/android/uncertified/  poi riavvia.

Condividere cartelle host con Android (Galleria vede ~/Immagini, ecc.):
  androidbox-share                # default dai tuoi XDG dir (Pictures/Download/…)
  androidbox-share ~/dir [Subdir] # condividi una cartella specifica
  androidbox-share --list         # mostra le condivisioni + stato
  androidbox-unshare --all        # rimuove tutto (cartelle host intatte)

Spegnere (e non farlo tornare al boot):  androidbox-stop
Stato:                                   androidbox-status
──────────────────────────────────────────────────────────────────────────
EOF
ok "Fatto."
