#!/usr/bin/env bash
set -euo pipefail
: "${RENDER_API_KEY:?export RENDER_API_KEY=rnd_...}"
OUT="${HOME}/.cache/p12/services.json"
HOST="api.render.com"; PORT="443"
URL="https://${HOST}/v1/services?limit=200"
mkdir -p "${HOME}/.cache/p12"

doh_ips(){ for u in \
  "https://1.1.1.1/dns-query?name=${HOST}&type=A" \
  "https://1.0.0.1/dns-query?name=${HOST}&type=A"
do curl -sS -H 'accept: application/dns-json' "$u" \
   | grep -oE '"data":"([0-9]{1,3}\.){3}[0-9]{1,3}"' \
   | cut -d':' -f2 | tr -d '"'; done | sort -u; }

ok=1
while IFS= read -r ip; do
  if curl -sS --resolve "${HOST}:${PORT}:${ip}" \
       -H "Authorization: Bearer ${RENDER_API_KEY}" \
       -H "Accept: application/json" "$URL" -o "$OUT"; then ok=0; break; fi
done < <(doh_ips)
[ $ok -eq 0 ] || { echo "ERROR: no pude listar servicios"; exit 2; }
echo "OK: ${OUT}"
