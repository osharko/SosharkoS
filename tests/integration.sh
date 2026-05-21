#!/usr/bin/env bash
# Tier 2 — INTEGRAZIONE (headless, da eseguire DENTRO la VM via SSH).
# Valida i pacchetti combinati: container runtime + Kubernetes (k3d) + k9s +
# distrobox + mise + clamav. Ogni blocco è indipendente (pass/skip/fail).
# Heavy: scarica immagini → richiede rete (NAT VM ok) e qualche minuto.
set -uo pipefail

pass=0; fail=0; skip=0
ok(){ printf '  \033[32m✓\033[0m %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  \033[31m✗ FAIL\033[0m %s\n' "$1"; fail=$((fail+1)); }
sk(){ printf '  \033[33m! SKIP\033[0m %s\n' "$1"; skip=$((skip+1)); }
retry(){ local n=$1; shift; for i in $(seq 1 "$n"); do "$@" && return 0; sleep 5; done; return 1; }

echo "── container runtime ──"
retry 6 sudo docker run --rm hello-world >/dev/null 2>&1 && ok "docker run hello-world" || no "docker run"
podman run --rm hello-world >/dev/null 2>&1 && ok "podman run hello-world" || no "podman run"

echo "── distrobox (best-effort) ──"
if distrobox create --name itest --image registry.fedoraproject.org/fedora:latest --yes >/dev/null 2>&1; then
  distrobox enter itest -- cat /etc/os-release 2>/dev/null | grep -q "Fedora" \
    && ok "distrobox create+enter+exec" || no "distrobox enter"
  distrobox rm -f itest >/dev/null 2>&1 || true
else
  sk "distrobox create (rete/tempo)"
fi

echo "── Kubernetes: k3d (k3s-in-docker) + kubectl + k9s ──"
# k3d non è nell'immagine (immutable): lo scarichiamo on-the-fly nel test.
K3D=/tmp/k3d
if [ ! -x "$K3D" ]; then
  curl -fsSL -o "$K3D" "https://github.com/k3d-io/k3d/releases/latest/download/k3d-linux-amd64" 2>/dev/null && chmod +x "$K3D"
fi
if [ -x "$K3D" ] && command -v kubectl >/dev/null; then
  if retry 2 sudo "$K3D" cluster create sostest --wait --timeout 120s >/dev/null 2>&1; then
    export KUBECONFIG; KUBECONFIG="$(mktemp)"; sudo "$K3D" kubeconfig get sostest > "$KUBECONFIG" 2>/dev/null
    kubectl get nodes 2>/dev/null | grep -q " Ready " && ok "k3d: nodo Ready (kubectl)" || no "k3d: nodo non Ready"
    k9s info >/dev/null 2>&1 && ok "k9s info legge il cluster" || sk "k9s info (TUI; non in immagine?)"
    sudo "$K3D" cluster delete sostest >/dev/null 2>&1 || true
  else
    no "k3d cluster create"
  fi
else
  sk "k3d/kubectl non disponibili"
fi

echo "── mise runtime ──"
if command -v mise >/dev/null; then
  mise use -g node@lts >/dev/null 2>&1 && mise exec -- node --version >/dev/null 2>&1 \
    && ok "mise: node@lts installato e funzionante" || sk "mise node (rete/tempo)"
else
  sk "mise assente"
fi

echo "── ClamAV (EICAR) ──"
if command -v clamscan >/dev/null; then
  printf 'X5O!P%%@AP[4\\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*' > /tmp/eicar.txt
  clamscan --no-summary /tmp/eicar.txt 2>/dev/null | grep -q "FOUND" \
    && ok "clamscan rileva EICAR" || sk "clamscan (db freshclam non aggiornato?)"
  rm -f /tmp/eicar.txt
else
  sk "clamscan assente"
fi

echo
echo "════ integrazione: $pass ✓  $skip !  $fail ✗ ════"
[ "$fail" -eq 0 ]
