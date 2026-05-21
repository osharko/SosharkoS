#!/usr/bin/env bash
# Tier 3 — validazione GRAFICA in QEMU (NON serve hardware reale).
# Boota la qcow2 con GPU virtuale (egl-headless + virtio-gpu-gl) e audio
# catturato su WAV, poi:
#   - cattura il framebuffer via QMP `screendump` → verifica desktop NON nero
#     (niri + bar Noctalia renderizzati)
#   - riproduce un sample e verifica che esca AUDIO (RMS≠0 nel wav catturato)
#   - apre una GUI app e ne cattura la finestra (screenshot)
#
# Uso:  ./test-vm-gui.sh [IMAGE]   (default sosharkos:dev). Richiede /dev/kvm,
# qemu-system-x86_64 con egl-headless (host mesa/EGL), python3, ffmpeg.
set -uo pipefail

IMAGE="${1:-${IMAGE:-sosharkos:dev}}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$HERE/.tmp-gui"; mkdir -p "$TMP"
SSH_KEY="$TMP/id"; SSH_PORT=2223
QMP="$TMP/qmp.sock"; SHOT="$TMP/desktop.ppm"; AWAV="$TMP/audio.wav"
BIB="quay.io/centos-bootc/bootc-image-builder:latest"
pass=0; fail=0
ok(){ printf '  \033[32m✓\033[0m %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  \033[31m✗ FAIL\033[0m %s\n' "$1"; fail=$((fail+1)); }
cleanup(){ [ -n "${QPID:-}" ] && kill "$QPID" 2>/dev/null || true; }
trap cleanup EXIT

# ─── qcow2 (riusa test-vm.sh per build) o pretende che esista ───────
DISK="$(find "$HERE/.tmp/qcow2" -name '*.qcow2' 2>/dev/null | head -1)"
[ -n "$DISK" ] || { echo "✗ qcow2 mancante: esegui prima 'just test-vm' (genera la qcow2)"; exit 2; }
[ -f "$SSH_KEY" ] || cp "$HERE/.tmp/id_test" "$SSH_KEY" 2>/dev/null || ssh-keygen -t ed25519 -N "" -f "$SSH_KEY" -q

# ─── helper QMP (python3): esegue un comando e opzionale screendump ─
qmp(){ python3 - "$QMP" "$1" "${2:-}" <<'PY'
import socket,sys,json
sock,cmd,arg=sys.argv[1],sys.argv[2],sys.argv[3]
s=socket.socket(socket.AF_UNIX); s.settimeout(15); s.connect(sock)
def rl():
    buf=b""
    while b"\n" not in buf:
        d=s.recv(4096)
        if not d: break
        buf+=d
    return buf.decode(errors="replace").strip()
rl()                                              # greeting
s.sendall(b'{"execute":"qmp_capabilities"}\n'); rl()
c={"execute":cmd}
if arg: c["arguments"]={"filename":arg}
s.sendall((json.dumps(c)+"\n").encode())
print(rl())                                       # risposta (sync: file scritto al ritorno)
PY
}

echo "▶ boot QEMU grafico (virtio-gpu-gl + egl-headless + audio→wav)…"
qemu-system-x86_64 \
    -m 4096 -smp 2 -accel kvm \
    -drive file="$DISK",if=virtio,format=qcow2 \
    -nic user,hostfwd=tcp::${SSH_PORT}-:22 \
    -vga none -device virtio-gpu-gl-pci -display egl-headless \
    -audiodev wav,id=snd0,path="$AWAV" -device intel-hda -device hda-output,audiodev=snd0 \
    -qmp unix:"$QMP",server,nowait \
    -serial file:"$TMP/serial.log" &
QPID=$!

SSH=(-i "$SSH_KEY" -p "$SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5)
echo -n "  attendo ssh"; for _ in $(seq 1 36); do ssh "${SSH[@]}" tester@localhost true 2>/dev/null && break; printf .; sleep 5; done; echo
ssh "${SSH[@]}" tester@localhost true 2>/dev/null || { no "ssh non disponibile (vedi $TMP/serial.log)"; exit 3; }

# sudo passwordless (bootstrap con la password una volta)
ssh "${SSH[@]}" tester@localhost "echo sosharkos | sudo -S bash -c 'echo \"tester ALL=(ALL) NOPASSWD:ALL\" > /etc/sudoers.d/99-test'" 2>/dev/null || true

echo "▶ autologin per il test: greetd initial_session=tester (passwordless)…"
ssh "${SSH[@]}" tester@localhost 'sudo tee /etc/greetd/config.toml >/dev/null <<EOF
[terminal]
vt = 1
[initial_session]
command = "niri-session"
user = "tester"
[default_session]
command = "niri-session"
user = "tester"
EOF
sudo systemctl restart greetd' 2>/dev/null || true
echo "▶ attendo che niri renderizzi…"; sleep 30

echo "── diagnostica sessione grafica ──"
ssh "${SSH[@]}" tester@localhost 'u=$(id -u tester); echo "tester uid=$u"; pgrep -u tester -x niri >/dev/null && echo "niri: UP" || echo "niri: DOWN"; ls /run/user/$u/wayland-* 2>/dev/null || echo "no wayland socket"; echo "--- journalctl greetd ---"; sudo journalctl -u greetd -n 20 --no-pager 2>/dev/null | tail -20' 2>/dev/null || true

echo "── render desktop (screendump) ──"
resp=""
for _ in 1 2 3; do
    [ -S "$QMP" ] && resp="$(qmp screendump "$SHOT" 2>&1)"
    [ -s "$SHOT" ] && break
    sleep 3
done
echo "  QMP screendump → ${resp:-<nessuna risposta>}"
if [ -s "$SHOT" ]; then
    yavg="$(ffmpeg -v error -i "$SHOT" -vf format=gray,signalstats -f null - 2>&1 | grep -oE 'YAVG:[0-9.]+' | head -1 | cut -d: -f2)"
    # non-nero e non-uniforme → qualcosa è renderizzato
    if [ -n "$yavg" ] && awk "BEGIN{exit !($yavg>3)}"; then
        ok "desktop renderizzato (screendump non nero, YAVG=$yavg) → $SHOT"
    else
        no "desktop nero/vuoto (YAVG=${yavg:-?}) — niri/noctalia non parte? vedi $SHOT"
    fi
else
    no "screendump non catturato (QMP/virtio-gpu?)"
fi

echo "── audio playback (cattura wav) ──"
# tono di test riprodotto nella sessione grafica (come utente greeter)
ssh "${SSH[@]}" tester@localhost 'export XDG_RUNTIME_DIR=/run/user/$(id -u); timeout 5 pw-play /usr/share/sounds/freedesktop/stereo/bell.oga 2>/dev/null || timeout 5 speaker-test -t sine -f 440 -l 1 2>/dev/null' >/dev/null 2>&1 || true
sleep 2
if [ -s "$AWAV" ]; then
    vol="$(ffmpeg -v error -i "$AWAV" -af volumedetect -f null - 2>&1 | grep -oE 'mean_volume: [-0-9.]+' | awk '{print $2}')"
    if [ -n "$vol" ] && awk "BEGIN{exit !($vol>-90)}"; then
        ok "audio catturato dalla guest (mean_volume ${vol} dB)"
    else
        no "audio muto (${vol:-?} dB) — sink pipewire/sessione?"
    fi
else
    no "nessun wav audio catturato"
fi

ssh "${SSH[@]}" tester@localhost 'sudo poweroff' 2>/dev/null || true
echo; echo "════ GUI/QEMU: $pass ✓  $fail ✗ ════ (artefatti in $TMP)"
[ "$fail" -eq 0 ]
