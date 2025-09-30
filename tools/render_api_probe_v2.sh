#!/usr/bin/env bash
set -euo pipefail
: "${RENDER_API_KEY:?export RENDER_API_KEY=...}"
: "${RENDER_SERVICE_ID:?export RENDER_SERVICE_ID=srv-...}"
HOST="api.render.com"; PORT="443"
URL="https://${HOST}/v1/services/${RENDER_SERVICE_ID}/deploys?limit=5"

doh_ips(){ for u in "https://1.1.1.1/dns-query?name=${HOST}&type=A" "https://1.0.0.1/dns-query?name=${HOST}&type=A"; do
  curl -sS -H 'accept: application/dns-json' "$u" \
  | grep -oE '"data":"([0-9]{1,3}\.){3}[0-9]{1,3}"' | cut -d':' -f2 | tr -d '"'
done | sort -u; }

fetch_json(){
  local ok=1
  while IFS= read -r ip; do
    if curl -sS --resolve "${HOST}:${PORT}:${ip}" \
         -H "Authorization: Bearer ${RENDER_API_KEY}" -H "Accept: application/json" \
         "$URL"; then ok=0; break; fi
  done < <(doh_ips)
  return $ok
}

json="$(fetch_json)" || { echo "ERROR: no pude consultar Deploys (API)"; exit 2; }

python - <<'PY' <<<"$json"
import json, sys
arr=json.load(sys.stdin)
for d in arr:
  print(f"id={d.get('id')} status={d.get('status')} commit={d.get('commitId')} createdAt={d.get('createdAt')}")
PY
