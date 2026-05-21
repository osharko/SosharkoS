#!/usr/bin/env bash
# SOsharkOS — onboarding primo login (§17).
# I package manager (mise/brew/flatpak/distrobox) sono già nell'immagine; qui
# scegli COSA installarci sopra. Tutto in /home o /var: NON tocca l'immutabile.
# Idempotente: marker per-utente. Rilanciabile con `sosharkos-onboard`.
set -uo pipefail

MARKER="${XDG_STATE_HOME:-$HOME/.local/state}/sosharkos/onboarded"
FORCE="${1:-}"
[ "$FORCE" != "--force" ] && [ -f "$MARKER" ] && exit 0
command -v gum >/dev/null || { echo "gum non disponibile"; exit 0; }

gum style --border rounded --margin 1 --padding "1 2" \
  "SOsharkOS — onboarding" \
  "Tutto opzionale e rimovibile. Niente tocca il sistema immutabile."

SEL="$(gum choose --no-limit \
  --selected="brew,mise: runtime LTS,flatpak: extra" \
  "brew" \
  "mise: runtime LTS" \
  "flatpak: extra" \
  "distrobox: box dev (fedora)")" || exit 0

has(){ printf '%s\n' "$SEL" | grep -qF "$1"; }

if has "brew"; then
  if ! command -v brew >/dev/null && [ ! -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
    echo "→ installo Homebrew (in /home/linuxbrew)…"
    NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
fi

if has "mise: runtime LTS"; then
  echo "→ mise: python/node/java/go/dotnet (LTS)…"
  mise use -g python@latest node@lts java@lts go@latest dotnet@latest
fi

if has "flatpak: extra"; then
  # Lista extra da concordare (oltre alla baseline di flatpaks.list).
  EXTRA_FLATPAKS=()   # es: org.gimp.GIMP com.discordapp.Discord
  [ "${#EXTRA_FLATPAKS[@]}" -gt 0 ] && \
    flatpak install -y --noninteractive flathub "${EXTRA_FLATPAKS[@]}" || \
    echo "  (nessun flatpak extra configurato)"
fi

if has "distrobox: box dev"; then
  echo "→ distrobox: box 'dev' (fedora:latest)…"
  distrobox create -Y -n dev -i registry.fedoraproject.org/fedora:latest || true
fi

mkdir -p "$(dirname "$MARKER")"; touch "$MARKER"
gum style --foreground 42 "Fatto. Rilancia quando vuoi con: sosharkos-onboard --force"
