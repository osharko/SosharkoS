#!/usr/bin/env bash
# Tier 2/3 — smoke FUNZIONALE, da eseguire DENTRO il sistema avviato
# (VM via test-vm.sh, o a mano post-install). Verifica che le cose FUNZIONINO,
# non solo che siano installate.
set -uo pipefail

pass=0; fail=0; warn=0
ok(){ printf '  \033[32m✓\033[0m %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  \033[31m✗ FAIL\033[0m %s\n' "$1"; fail=$((fail+1)); }
wn(){ printf '  \033[33m! WARN\033[0m %s\n' "$1"; warn=$((warn+1)); }
retry(){ local n=$1; shift; for i in $(seq 1 "$n"); do "$@" && return 0; sleep 5; done; return 1; }

echo "── systemd (attendo che finisca il boot) ──"
state=""
for _ in $(seq 1 24); do                      # max ~2 min
    state="$(systemctl is-system-running 2>/dev/null || true)"
    case "$state" in running|degraded) break;; esac
    sleep 5
done
failed="$(systemctl --failed --no-legend 2>/dev/null | awk '{print $1}' | tr '\n' ' ')"
case "$state" in
    running)  ok "system is-system-running (running)";;
    degraded) wn "system degraded — unit fallite: $failed";;
    *)  if [ -z "$failed" ]; then
            wn "system '$state' (boot non ancora finito — es. flatpak first-boot in download; nessuna unit fallita)"
        else
            no "system '$state' con unit FALLITE: $failed"
        fi;;
esac

echo "── servizi chiave ──"
systemctl is-active --quiet NetworkManager.service && ok "active NetworkManager" || no "NetworkManager non active"
systemctl is-active --quiet docker.socket && ok "active docker.socket" || no "docker.socket non active"
for u in bluetooth.service libvirtd.service; do
    systemctl is-active --quiet "$u" && ok "active $u" || wn "non active $u (atteso in VM/headless)"
done
systemctl --user is-active --quiet pipewire 2>/dev/null && ok "pipewire (user)" || wn "pipewire user non rilevato (serve sessione grafica)"

echo "── runtime funzionali ──"
retry 6 sudo docker run --rm hello-world >/dev/null 2>&1 && ok "docker run hello-world" || no "docker run (rete/daemon)"
distrobox version >/dev/null 2>&1 && ok "distrobox version" || no "distrobox ko"
kubectl version --client >/dev/null 2>&1 && ok "kubectl client" || no "kubectl ko"
mise --version >/dev/null 2>&1 && ok "mise" || no "mise ko"
flatpak remotes 2>/dev/null | grep -qi flathub && ok "flathub remote (first-boot ok)" || wn "flathub non ancora configurato"

echo "── desktop bits ──"
niri --version >/dev/null 2>&1 && ok "niri" || no "niri ko"
command -v qs >/dev/null && ok "qs (noctalia-qs) presente" || wn "qs assente"

echo "── codec (decoder, ciò che serve al playback) ──"
decs="$(ffmpeg -hide_banner -decoders 2>/dev/null)"
for c in h264 hevc av1 aac; do
    grep -qiw "$c" <<<"$decs" && ok "decoder $c" || no "decoder $c mancante"
done
command -v vainfo >/dev/null && { vainfo >/dev/null 2>&1 && ok "vainfo VAAPI" || wn "vainfo ko (normale in VM senza GPU)"; } || wn "vainfo assente"

echo
echo "════ smoke: $pass ✓   $warn !   $fail ✗ ════"
[ "$fail" -eq 0 ]
