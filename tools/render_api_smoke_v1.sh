#!/usr/bin/env bash
set -euo pipefail
: "${RENDER_API_KEY:?export RENDER_API_KEY=...}"
: "${RENDER_SERVICE_ID:?export RENDER_SERVICE_ID=srv-...}"
HOST="api.render.com"; PORT="443"
URL="https://${HOST}/v1/services/${RENDER_SERVICE_ID}"

doh_ips(){ for u in "https://1.1.1.1/dns-query?name=${HOST}&type=A" "https://1.0.0.1/dns-query?name=${HOST}&type=A"; do
  curl -sS -H 'accept: application/dns-json' "$u" \
  | grep -oE '"data":"([0-9]{1,3}\.){3}[0-9]{1,3}"' | cut -d':' -f2 | tr -d '"'
done | sort -u; }

code=""
while IFS= read -r ip; do
  code="$(curl -sS -o /dev/null -w '%{http_code}' --resolve "${HOST}:${PORT}:${ip}" \
    -H "Authorization: Bearer ${RENDER_API_KEY}" -H "Accept: application/json" "$URL" || true)"
  [[ "$code" =~ ^[0-9]{3}$ ]] && break
done < <(doh_ips)

echo "API /services/<id> HTTP=$code"
[[ "$code" == "200" ]] || exit 2
