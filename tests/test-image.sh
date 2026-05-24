#!/usr/bin/env bash
# Tier 1 — introspezione immagine (NESSUN boot).
# Esegue comandi DENTRO l'immagine OCI via podman e verifica che pacchetti,
# unit, file e codec attesi ci siano. Deterministico, veloce, CI-friendly.
#
# Uso:  ./tests/test-image.sh [IMAGE]      (default: sosharkos:dev)
set -uo pipefail

IMAGE="${1:-${IMAGE:-sosharkos:dev}}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/expectations.sh"

pass=0; fail=0
ok(){ printf '  \033[32m✓\033[0m %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  \033[31m✗ FAIL\033[0m %s\n' "$1"; fail=$((fail+1)); }

# Esegue uno snippet bash dentro l'immagine (entrypoint neutralizzato).
# --network=none: i check non usano rete + evita fallimenti di setup rete
# rootless (slirp/pasta) su runner CI → altrimenti OGNI podman run fallirebbe.
inimg(){ podman run --rm --network=none --entrypoint "" "$IMAGE" bash -lc "$1" 2>/dev/null; }

echo "▶ Test immagine: $IMAGE"
if ! podman image exists "$IMAGE"; then
    echo "✗ immagine '$IMAGE' non trovata — esegui 'just build' prima." >&2
    exit 2
fi

echo "── binari nel PATH ──"
for b in "${EXPECT_BINS[@]}"; do
    inimg "command -v '$b' >/dev/null" && ok "bin $b" || no "bin $b mancante"
done

echo "── pacchetti RPM ──"
for p in "${EXPECT_RPMS[@]}"; do
    inimg "rpm -q '$p' >/dev/null" && ok "rpm $p" || no "rpm $p non installato"
done

echo "── unit systemd enabled ──"
for u in "${EXPECT_UNITS_ENABLED[@]}"; do
    state="$(inimg "systemctl is-enabled '$u' 2>/dev/null")"
    [ "$state" = "enabled" ] && ok "unit $u ($state)" || no "unit $u = '${state:-assente}'"
done

echo "── file presenti ──"
for f in "${EXPECT_FILES[@]}"; do
    inimg "test -e '$f'" && ok "file $f" || no "file $f mancante"
done

echo "── os-release ──"
inimg "grep -q '$EXPECT_OSRELEASE_GREP' /etc/os-release" \
    && ok "os-release contiene $EXPECT_OSRELEASE_GREP" \
    || no "os-release senza $EXPECT_OSRELEASE_GREP"

echo "── codec ffmpeg ──"
for enc in "${EXPECT_FFMPEG_ENCODERS[@]}"; do
    inimg "ffmpeg -hide_banner -encoders 2>/dev/null | grep -qw '$enc'" \
        && ok "ffmpeg encoder $enc" || no "ffmpeg encoder $enc mancante"
done

echo "── flatpaks.list ──"
for fp in "${EXPECT_FLATPAKS[@]}"; do
    inimg "grep -qx '$fp' /usr/share/sosharkos/flatpaks.list" \
        && ok "flatpak listato $fp" || no "flatpak $fp non in flatpaks.list"
done

echo "── bootc lint ──"
inimg "bootc container lint >/dev/null 2>&1" && ok "bootc container lint" || no "bootc lint"

echo
echo "════ Risultato: $pass ✓   $fail ✗ ════"
[ "$fail" -eq 0 ]
