#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR]}"
OUTDIR="${2:-$HOME/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
DEST="${OUTDIR}/runtime-diag-${TS}"
mkdir -p "$DEST"
urls=(
  "/" "/index.html" "/terms" "/privacy" "/api/health"
  "/api/deploy-stamp" "/api/notes" "/api/notes?limit=10"
)
printf "url\tcode\tlen\n" > "${DEST}/summary.tsv"
for u in "${urls[@]}"; do
  b="${DEST}$(echo "$u" | sed 's#[/?&=]#_#g').body"
  code=$(curl -sS -D "${b}.hdr" -o "${b}.bin" -w '%{http_code}' "$BASE$u" || true)
  len=$(wc -c < "${b}.bin" || echo 0)
  # para HTML, guardar una vista de texto para inspección rápida
  ct=$(sed -n 's/^[Cc]ontent-[Tt]ype:[[:space:]]*//p' "${b}.hdr" | tr -d '\r' | head -1)
  if echo "$ct" | grep -qi 'text/html'; then
    sed -n '1,200p' "${b}.bin" > "${b}.txt" || true
  fi
  printf "%s\t%s\t%s\n" "$u" "$code" "$len" >> "${DEST}/summary.tsv"
done
echo "OK: resumen en ${DEST}/summary.tsv"
