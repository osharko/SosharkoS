#!/usr/bin/env bash
# Tier 2 — validazione CODEC (headless, niente display).
# Scarica sample h264/HEVC/AV1 e li DECODIFICA: decode-to-null + estrazione di
# 1 frame (PNG non-nero) + audio (WAV con RMS≠0 se presente). Conferma che i
# codec pieni (rpmfusion) funzionano davvero, non solo che il pacchetto c'è.
# Il PLAYBACK percepito (video nitido + suono in cuffia) resta validazione umana.
set -uo pipefail

DL="${TMPDIR:-/tmp}/sos-codec-samples"; mkdir -p "$DL"
pass=0; fail=0; skip=0
ok(){ printf '  \033[32m✓\033[0m %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  \033[31m✗ FAIL\033[0m %s\n' "$1"; fail=$((fail+1)); }
sk(){ printf '  \033[33m! SKIP\033[0m %s\n' "$1"; skip=$((skip+1)); }

command -v ffmpeg >/dev/null || { echo "ffmpeg assente"; exit 2; }

# Sample piccoli (~1MB) da test-videos.co.uk: stessa clip in 3 codec.
BASE="https://test-videos.co.uk/vids/bigbuckbunny"
declare -A SAMPLES=(
  [h264]="$BASE/mp4/h264/360/Big_Buck_Bunny_360_10s_1MB.mp4"
  [hevc]="$BASE/mp4/hevc/360/Big_Buck_Bunny_360_10s_1MB.mp4"
  [av1]="$BASE/mp4/av1/360/Big_Buck_Bunny_360_10s_1MB.mp4"
)

for codec in h264 hevc av1; do
  url="${SAMPLES[$codec]}"; f="$DL/$codec.mp4"
  if [ ! -s "$f" ]; then
    curl -fsSL --retry 2 -o "$f" "$url" 2>/dev/null || { sk "$codec: download fallito (rete?)"; continue; }
  fi
  # 1) decode-to-null: 0 errori = codec ok
  if ffmpeg -v error -i "$f" -f null - 2>/tmp/sos-ff.err && [ ! -s /tmp/sos-ff.err ]; then
    ok "$codec: decode-to-null pulito"
  else
    no "$codec: decode errori → $(head -1 /tmp/sos-ff.err)"; continue
  fi
  # 2) estrai 1 frame PNG e verifica che non sia vuoto/nero
  if ffmpeg -v error -i "$f" -frames:v 1 -y "$DL/$codec.png" 2>/dev/null && \
     [ "$(stat -c%s "$DL/$codec.png" 2>/dev/null || echo 0)" -gt 2000 ]; then
    ok "$codec: frame PNG estratto ($(stat -c%s "$DL/$codec.png") B)"
  else
    no "$codec: frame non estratto"
  fi
done

# 3) audio: decodifica la traccia (se presente) e verifica energia ≠ 0
f="$DL/h264.mp4"
if [ -s "$f" ] && ffmpeg -v error -i "$f" -map a:0 -t 1 -f wav -y "$DL/a.wav" 2>/dev/null && [ -s "$DL/a.wav" ]; then
  vol="$(ffmpeg -v error -i "$DL/a.wav" -af volumedetect -f null - 2>&1 | grep -oE 'mean_volume: [-0-9.]+' | awk '{print $2}')"
  if [ -n "$vol" ] && [ "${vol%.*}" != "-91" ] && [ "${vol%.*}" -gt -90 ] 2>/dev/null; then
    ok "audio: traccia decodificata (mean_volume ${vol} dB)"
  else
    sk "audio: traccia muta o assente (sample video-only)"
  fi
else
  sk "audio: nessuna traccia audio nel sample"
fi

echo
echo "════ codec: $pass ✓  $skip !  $fail ✗ ════"
[ "$fail" -eq 0 ]
