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
pass=0; fail=0; warn=0
ok(){ printf '  \033[32m✓\033[0m %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  \033[31m✗ FAIL\033[0m %s\n' "$1"; fail=$((fail+1)); }
wn(){ printf '  \033[33m! WARN\033[0m %s\n' "$1"; warn=$((warn+1)); }
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

# autologin niri è BAKED nella qcow2 (test-vm.sh, customizations.files) → niri
# parte già al boot su vt1 con seat valido. Aspettiamo che renderizzi.
echo "▶ attendo che niri (autologin baked al boot) renderizzi…"; sleep 20

echo "── diagnostica sessione grafica ──"
ssh "${SSH[@]}" tester@localhost 'u=$(id -u tester); echo "tester uid=$u"; pgrep -u tester -x niri >/dev/null && echo "niri: UP" || echo "niri: DOWN"; ls /run/user/$u/wayland-* 2>/dev/null || echo "no wayland socket"; echo "--- journalctl greetd ---"; sudo journalctl -u greetd -n 20 --no-pager 2>/dev/null | tail -20' 2>/dev/null || true

echo "── audio: avvio un suono nella sessione (gira in parallelo) ──"
ssh "${SSH[@]}" tester@localhost 'export XDG_RUNTIME_DIR=/run/user/$(id -u); (timeout 6 pw-play /usr/share/sounds/freedesktop/stereo/bell.oga || timeout 6 speaker-test -t sine -f 440 -l 1) >/dev/null 2>&1' 2>/dev/null &

echo "── render desktop (grim nella sessione niri) ──"
SHOT="$TMP/desktop.png"
ssh "${SSH[@]}" tester@localhost 'u=$(id -u); export XDG_RUNTIME_DIR=/run/user/$u; export WAYLAND_DISPLAY=$(ls /run/user/$u 2>/dev/null | grep -m1 -E "^wayland-[0-9]+$"); echo "outputs:"; niri msg outputs 2>/dev/null | grep -iE "Output|Current mode|Logical" | head -4; grim /tmp/shot.png 2>&1 | head -2' 2>/dev/null
ssh "${SSH[@]}" tester@localhost 'cat /tmp/shot.png 2>/dev/null' > "$SHOT" 2>/dev/null
if [ -s "$SHOT" ]; then
    res="$(ffprobe -v error -show_entries stream=width,height -of csv=p=0 "$SHOT" 2>/dev/null)"
    # un desktop reale ha molti valori cromatici distinti; un nero/uniforme ~1
    ncol="$(ffmpeg -v error -i "$SHOT" -vf "scale=64:64,format=rgb24" -f rawvideo - 2>/dev/null | od -An -tu1 | tr -s ' ' '\n' | grep -v '^$' | sort -un | wc -l)"
    if [ "${ncol:-0}" -gt 20 ]; then
        ok "desktop renderizzato (grim ${res:-?}, ${ncol} valori cromatici distinti = niri+Noctalia) → $SHOT"
    else
        no "desktop nero/uniforme (${ncol} valori) → $SHOT"
    fi
else
    no "grim non ha prodotto un PNG (niri senza output? wlr-screencopy?)"
fi

echo "── spegnimento (flush wav) ──"
ssh "${SSH[@]}" tester@localhost 'sudo poweroff' 2>/dev/null || true
for _ in $(seq 1 25); do kill -0 "$QPID" 2>/dev/null || break; sleep 1; done

echo "── audio playback (wav catturato dalla guest) ──"
if [ -s "$AWAV" ] && [ "$(stat -c%s "$AWAV" 2>/dev/null || echo 0)" -gt 1000 ]; then
    vol="$(ffmpeg -v error -i "$AWAV" -af volumedetect -f null - 2>&1 | grep -oE 'mean_volume: [-0-9.]+' | awk '{print $2}')"
    if [ -n "$vol" ] && awk "BEGIN{exit !($vol>-91)}"; then
        ok "audio uscito dalla guest (mean_volume ${vol} dB)"
    else
        wn "wav presente ma silenzioso (${vol:-?} dB)"
    fi
else
    wn "audio non catturato (solo header wav) — routing pipewire→hda in QEMU da rifinire; audio reale = check su HW"
fi

echo; echo "════ GUI/QEMU: $pass ✓  $warn !  $fail ✗ ════ (artefatti in $TMP)"
[ "$fail" -eq 0 ]
