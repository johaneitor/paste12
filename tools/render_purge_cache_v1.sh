#!/usr/bin/env bash
set -euo pipefail
API_KEY="${RENDER_API_KEY:?}"; SERVICE_ID="${RENDER_SERVICE_ID:?}"
HOST="api.render.com"; PORT="443"
URL="https://${HOST}/v1/services/${SERVICE_ID}/cache/purge"

doh_ips(){ for u in "https://1.1.1.1/dns-query?name=${HOST}&type=A" "https://1.0.0.1/dns-query?name=${HOST}&type=A"; do
  curl -sS -H 'accept: application/dns-json' "$u" | grep -oE '"data":"([0-9]{1,3}\.){3}[0-9]{1,3}"' | cut -d':' -f2 | tr -d '"'
done | sort -u; }

while IFS= read -r ip; do
  curl -sS --resolve "${HOST}:${PORT}:${ip}" -X POST \
    -H "Authorization: Bearer ${API_KEY}" -H "Accept: application/json" "$URL" -o /dev/null && { echo "OK: cache purged"; exit 0; }
done < <(doh_ips)
echo "WARN: no se pudo purgar (quizás no hay cache habilitado)"
