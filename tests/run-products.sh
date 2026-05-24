#!/usr/bin/env bash
# Esegue i descrittori per-prodotto tests/products/*.yaml.
#
# Ogni test ha un 'level' (headless|display|human) e un 'context' (image|vm):
#   - headless + context combaciante → ESEGUE 'cmd' (exit 0 = pass)
#   - display/human → stampa SKIP + 'steps' (checklist da validare a mano)
#
# Uso:
#   ./run-products.sh --context image [--image sosharkos:dev] [prod...]
#   ./run-products.sh --context vm --ssh "ssh -p 2222 tester@localhost ..." [prod...]
#
# Richiede: yq (python-yq, sintassi jq) sull'host.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRODUCTS="$HERE/products"
CONTEXT="image"; IMAGE="sosharkos:dev"; SSHCMD=""
FILTER=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --context) CONTEXT="$2"; shift 2;;
        --image)   IMAGE="$2"; shift 2;;
        --ssh)     SSHCMD="$2"; shift 2;;
        *)         FILTER+=("$1"); shift;;
    esac
done
command -v yq >/dev/null || { echo "serve yq (python-yq)"; exit 2; }

pass=0; fail=0; skip=0
ok(){ printf '    \033[32m✓\033[0m %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '    \033[31m✗ FAIL\033[0m %s\n' "$1"; fail=$((fail+1)); }
sk(){ printf '    \033[33m· skip\033[0m %s (%s)\n' "$1" "$2"; skip=$((skip+1)); }

run_cmd(){  # esegue $1 nel contesto scelto
    case "$CONTEXT" in
        image) podman run --rm --network=none --entrypoint "" "$IMAGE" bash -lc "$1" >/dev/null 2>&1 ;;
        vm)    [ -n "$SSHCMD" ] && $SSHCMD "bash -lc '$1'" >/dev/null 2>&1 ;;
    esac
}

want(){ [ ${#FILTER[@]} -eq 0 ] && return 0; for p in "${FILTER[@]}"; do [ "$p" = "$1" ] && return 0; done; return 1; }

for f in "$PRODUCTS"/*.yaml; do
    [ -e "$f" ] || continue
    product="$(yq -r '.product' "$f")"
    want "$product" || continue
    printf '\n\033[1m▸ %s\033[0m — %s\n' "$product" "$(yq -r '.summary // ""' "$f")"
    n="$(yq -r '.tests | length' "$f")"
    for i in $(seq 0 $((n-1))); do
        name="$(yq -r ".tests[$i].name" "$f")"
        level="$(yq -r ".tests[$i].level // \"headless\"" "$f")"
        ctx="$(yq -r ".tests[$i].context // \"image\"" "$f")"
        cmd="$(yq -r ".tests[$i].cmd // \"\"" "$f")"
        if [ "$level" = "headless" ] && [ "$ctx" = "$CONTEXT" ] && [ -n "$cmd" ]; then
            run_cmd "$cmd" && ok "$name" || no "$name"
        elif [ "$level" = "headless" ]; then
            sk "$name" "headless/$ctx ≠ contesto $CONTEXT"
        else
            sk "$name" "$level — validazione manuale (vedi steps)"
        fi
    done
done

echo
echo "════ prodotti: $pass ✓   $skip ·   $fail ✗   (contesto: $CONTEXT) ════"
[ "$fail" -eq 0 ]
