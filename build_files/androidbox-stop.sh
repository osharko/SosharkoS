#!/usr/bin/env bash
# androidbox-stop — spegne l'UX Android (Waydroid) e ne IMPEDISCE il ritorno
# al boot/login. Disabilita (non solo stop) entrambe le unit:
#   - waydroid-session.service   (USER)   → disable --now
#   - waydroid-container.service (SYSTEM) → disable --now
# Dopo questo comando Android resta SPENTO finché non riesegui `androidbox-start`.
#
# Best-effort e idempotente: rieseguirlo a sistema già spento non dà errore.
set -uo pipefail

# mise-immune: /usr/bin davanti, così lo shebang `env python3` di waydroid usa il
# python di SISTEMA (con i binding dbus) e non quello eventuale di mise.
export PATH="/usr/bin:$PATH"

SYS_UNIT=waydroid-container.service
USR_UNIT=waydroid-session.service

say()  { printf '\033[1;36m▶\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[33m!\033[0m %s\n' "$*" >&2; }

# ── 0. Smonta le cartelle condivise (bind-mount) PRIMA di fermare ───────────
# Best-effort + idempotente: senza config è un no-op. Vanno smontate prima di
# fermare il container, altrimenti i bind restano appesi su <DATADIR>/media/0.
# NB: smonta solo i bind; le cartelle host restano INTATTE.
say "Smonto le cartelle condivise (se presenti)…"
if command -v androidbox-share >/dev/null; then
    androidbox-share --teardown-all 2>/dev/null \
        && ok "Cartelle condivise smontate." \
        || warn "Niente da smontare (nessuna condivisione attiva)."
else
    warn "androidbox-share non trovato: salto lo smontaggio condivisioni."
fi

# ── 1. Stop sessione Android (best-effort) ──────────────────────────────────
say "Fermo la sessione Android (best-effort)."
waydroid session stop 2>/dev/null && ok "Sessione fermata." || warn "Nessuna sessione attiva."

# ── 2. Sessione utente: disable + stop (non torna al login) ─────────────────
say "Disabilito e fermo $USR_UNIT (utente)."
systemctl --user disable --now "$USR_UNIT" 2>/dev/null \
    && ok "$USR_UNIT disabilitato." || warn "$USR_UNIT già disabilitato/assente."

# ── 3. Container di sistema: disable + stop (non parte al boot) ──────────────
say "Disabilito e fermo $SYS_UNIT (sistema)."
sudo systemctl disable --now "$SYS_UNIT" 2>/dev/null \
    && ok "$SYS_UNIT disabilitato." || warn "$SYS_UNIT già disabilitato/assente."

echo
ok "Android UX SPENTO. Non tornerà al boot/login. Riaccendi con: androidbox-start"
