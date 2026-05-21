#!/usr/bin/env bash
# Tier 2/3 — smoke FUNZIONALE, da eseguire DENTRO il sistema avviato
# (VM via test-vm.sh, o a mano dopo l'install). Verifica che le cose non solo
# siano installate ma FUNZIONINO: servizi su, runtime operativi, codec ok.
set -uo pipefail

pass=0; fail=0; warn=0
ok(){   printf '  \033[32m✓\033[0m %s\n' "$1"; pass=$((pass+1)); }
no(){   printf '  \033[31m✗ FAIL\033[0m %s\n' "$1"; fail=$((fail+1)); }
wn(){   printf '  \033[33m! WARN\033[0m %s\n' "$1"; warn=$((warn+1)); }

echo "── systemd ──"
state="$(systemctl is-system-running 2>/dev/null || true)"
case "$state" in
    running)  ok "system is-system-running ($state)";;
    degraded) wn "system degraded — unit fallite: $(systemctl --failed --no-legend | awk '{print $1}' | tr '\n' ' ')";;
    *)        no "system stato='$state'";;
esac

echo "── servizi chiave attivi ──"
for u in NetworkManager.service bluetooth.service docker.socket libvirtd.service; do
    systemctl is-active --quiet "$u" && ok "active $u" || wn "non active $u"
done
# pipewire è user-service: controllo nella sessione utente
systemctl --user is-active --quiet pipewire 2>/dev/null && ok "active pipewire (user)" || wn "pipewire user non rilevato (serve sessione utente)"

echo "── runtime funzionali ──"
docker run --rm hello-world >/dev/null 2>&1 && ok "docker run hello-world" || no "docker non funziona"
distrobox version >/dev/null 2>&1 && ok "distrobox version" || no "distrobox ko"
kubectl version --client >/dev/null 2>&1 && ok "kubectl client" || no "kubectl ko"
mise --version >/dev/null 2>&1 && ok "mise" || no "mise ko"
flatpak remotes 2>/dev/null | grep -qi flathub && ok "flathub remote presente" || wn "flathub non ancora configurato (first-boot?)"

echo "── desktop bits ──"
niri --version >/dev/null 2>&1 && ok "niri" || no "niri ko"
command -v noctalia-shell >/dev/null && ok "noctalia-shell presente" || wn "noctalia-shell assente"

echo "── codec ──"
ffmpeg -hide_banner -encoders 2>/dev/null | grep -qw libx264 && ok "ffmpeg libx264" || no "codec h264 mancante (RPM Fusion?)"
# VAAPI hardware decode (presente se §9 applicata + GPU esposta dalla VM)
command -v vainfo >/dev/null && { vainfo >/dev/null 2>&1 && ok "vainfo VAAPI" || wn "vainfo ko (normale in VM senza GPU passthrough)"; } || wn "vainfo non installato (libva-utils)"

echo
echo "════ smoke: $pass ✓   $warn !   $fail ✗ ════"
[ "$fail" -eq 0 ]
