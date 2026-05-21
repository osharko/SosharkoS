#!/usr/bin/env bash
# Tier 2/3 — build qcow2 → boot headless in QEMU → smoke funzionale via SSH.
# Automatizza la "run emulata + test pacchetti" senza intervento manuale.
#
# Uso:  ./tests/test-vm.sh [IMAGE]      (default: sosharkos:dev)
# Richiede: podman, qemu-system-x86_64, accesso /dev/kvm.
#
# ⚠️ Primo run da validare: la generazione qcow2 (bootc-image-builder) e il
#    boot QEMU dipendono dall'ambiente. Se l'SSH non sale, guarda serial.log.
set -uo pipefail

IMAGE="${1:-${IMAGE:-sosharkos:dev}}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$HERE/.tmp"; mkdir -p "$TMP"
QCOW_DIR="$TMP/qcow2"
SSH_KEY="$TMP/id_test"
SSH_PORT=2222
BIB="quay.io/centos-bootc/bootc-image-builder:latest"

cleanup(){ [ -n "${QEMU_PID:-}" ] && kill "$QEMU_PID" 2>/dev/null || true; }
trap cleanup EXIT

# ─── bib gira rootful: porta l'immagine nello storage di root ───────
# (se costruita rootless con `podman build`, root non la vede)
if ! sudo podman image exists "$IMAGE"; then
    echo "▶ copio l'immagine nello storage rootful (podman save | sudo load)…"
    podman save "$IMAGE" | sudo podman load
fi

# ─── chiave SSH effimera + config bootc-image-builder ───────────────
[ -f "$SSH_KEY" ] || ssh-keygen -t ed25519 -N "" -f "$SSH_KEY" -q
cat > "$TMP/bib-config.toml" <<EOF
[[customizations.user]]
name = "tester"
key = "$(cat "$SSH_KEY.pub")"
groups = ["wheel"]

[customizations.services]
enabled = ["sshd.service"]
EOF

# ─── build qcow2 ────────────────────────────────────────────────────
echo "▶ build qcow2 da $IMAGE (bootc-image-builder)…"
rm -rf "$QCOW_DIR"; mkdir -p "$QCOW_DIR"
sudo podman run --rm -it --privileged \
    --security-opt label=type:unconfined_t \
    -v "$TMP/bib-config.toml":/config.toml:ro \
    -v "$QCOW_DIR":/output \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    "$BIB" --type qcow2 --config /config.toml --local "$IMAGE"

DISK="$(find "$QCOW_DIR" -name '*.qcow2' | head -1)"
[ -n "$DISK" ] || { echo "✗ qcow2 non generato" >&2; exit 2; }

# ─── boot headless QEMU con port-forward SSH ────────────────────────
echo "▶ boot QEMU headless (ssh su :$SSH_PORT)…"
qemu-system-x86_64 \
    -m 4096 -smp 2 -accel kvm \
    -drive file="$DISK",if=virtio,format=qcow2 \
    -nic user,hostfwd=tcp::${SSH_PORT}-:22 \
    -display none -serial file:"$TMP/serial.log" &
QEMU_PID=$!

# ─── attende SSH (max ~3 min) ───────────────────────────────────────
SSH_OPTS=(-i "$SSH_KEY" -p "$SSH_PORT" -o StrictHostKeyChecking=no
          -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5)
echo -n "  attendo boot+ssh"
for _ in $(seq 1 36); do
    if ssh "${SSH_OPTS[@]}" tester@localhost true 2>/dev/null; then echo " ✓"; break; fi
    printf .; sleep 5
done
if ! ssh "${SSH_OPTS[@]}" tester@localhost true 2>/dev/null; then
    echo " ✗ SSH non disponibile — vedi $TMP/serial.log" >&2; exit 3
fi

# ─── esegue lo smoke dentro la VM ───────────────────────────────────
echo "▶ smoke funzionale dentro la VM:"
ssh "${SSH_OPTS[@]}" tester@localhost 'bash -s' < "$HERE/smoke.sh"
rc=$?

ssh "${SSH_OPTS[@]}" tester@localhost 'sudo poweroff' 2>/dev/null || true
exit $rc
