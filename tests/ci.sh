#!/usr/bin/env bash
# ENTRYPOINT UNICO della test-suite SOsharkOS.
# Lanciato IDENTICO da: pipeline GitHub Actions, `act` locale, e `just ci`.
# → niente divergenza locale↔CI: c'è UNA sola definizione di "cosa si testa".
#
#   tests/ci.sh             # tutto: build + Tier1 + per-prodotto (+ Tier2/3 se c'è /dev/kvm)
#   tests/ci.sh --no-vm     # solo build + Tier1 + per-prodotto (runner SENZA KVM, es. GHA hosted)
#   tests/ci.sh --vm-only   # solo Tier2/3 (boot/e2e/render) — richiede KVM + immagine già pronta
#   IMAGE=sosharkos:dev tests/ci.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
IMAGE="${IMAGE:-sosharkos:ci}"
MODE=all
case "${1:-}" in --no-vm) MODE=novm;; --vm-only) MODE=vmonly;; "") ;; *) echo "arg sconosciuto: $1"; exit 2;; esac

rc=0
step(){ printf '\n\033[1m══════ %s ══════\033[0m\n' "$1"; }
fail(){ printf '\033[31m✗ STEP FALLITO: %s\033[0m\n' "$1"; rc=1; }

if [ "$MODE" != vmonly ]; then
    step "BUILD ($IMAGE)"
    if podman image exists "$IMAGE"; then echo "(immagine già presente, skip build)"; \
    else podman build -t "$IMAGE" -f "$ROOT/Containerfile" "$ROOT" || fail "build"; fi

    step "TIER 1 — introspezione immagine"
    bash "$HERE/test-image.sh" "$IMAGE" || fail "tier1 test-image"

    step "PER-PRODOTTO (contesto image)"
    bash "$HERE/run-products.sh" --context image --image "$IMAGE" || fail "per-prodotto image"
fi

if [ "$MODE" != novm ]; then
    if [ -e /dev/kvm ]; then
        step "TIER 2 — boot VM + smoke + integrazione (k3d/k9s/clamav)"
        bash "$HERE/test-vm.sh" "$IMAGE" || fail "tier2 test-vm"
        step "TIER 3 — grafico (render niri+Noctalia in QEMU)"
        bash "$HERE/test-vm-gui.sh" "$IMAGE" || fail "tier3 test-vm-gui"
    else
        echo "▶ /dev/kvm assente → Tier2/3 (boot/e2e/render) saltati."
        echo "  Su CI: registrare un runner self-hosted con KVM (vedi docs/testing.md)."
        [ "$MODE" = vmonly ] && fail "vm-only richiesto ma niente /dev/kvm"
    fi
fi

echo; if [ "$rc" -eq 0 ]; then echo "✅ CI suite OK (mode=$MODE)"; else echo "❌ CI suite: ci sono fallimenti (mode=$MODE)"; fi
exit "$rc"
