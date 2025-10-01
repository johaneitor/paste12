#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR]}"
OUTDIR="${2:-$HOME/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
DEST="${OUTDIR}/runtime-smoke-get-${TS}"
mkdir -p "$DEST"
urls=("/" "/index.html" "/terms" "/privacy" "/api/health" "/api/deploy-stamp" "/api/notes" "/api/notes?limit=10")
printf "url\tcode\tlen\n" > "${DEST}/summary.tsv"
for u in "${urls[@]}"; do
  b="${DEST}$(echo "$u" | sed 's#[/?&=]#_#g').bin"
  code=$(curl -sS -X GET -D "${b}.hdr" -o "${b}" -w '%{http_code}' "$BASE$u" || true)
  len=$(wc -c < "${b}" || echo 0)
  printf "%s\t%s\t%s\n" "$u" "$code" "$len" >> "${DEST}/summary.tsv"
done
echo "OK: ${DEST}/summary.tsv"
