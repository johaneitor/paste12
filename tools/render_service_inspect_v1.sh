#!/usr/bin/env bash
set -euo pipefail
SERVICE_ID="${RENDER_SERVICE_ID:?Uso: export RENDER_SERVICE_ID=srv-...}"
API_KEY="${RENDER_API_KEY:?Uso: export RENDER_API_KEY=...}"
HOST="api.render.com"; PORT="443"; URL="https://${HOST}/v1/services/${SERVICE_ID}"

doh_ips(){ for u in "https://1.1.1.1/dns-query?name=${HOST}&type=A" "https://1.0.0.1/dns-query?name=${HOST}&type=A"; do
  curl -sS -H 'accept: application/dns-json' "$u" | grep -oE '"data":"([0-9]{1,3}\.){3}[0-9]{1,3}"' | cut -d':' -f2 | tr -d '"'
done | sort -u; }

ok=1
while IFS= read -r ip; do
  if curl -sS --resolve "${HOST}:${PORT}:${ip}" -H "Authorization: Bearer ${API_KEY}" -H "Accept: application/json" "$URL" -o /tmp/p12-svc.json; then ok=0; break; fi
done < <(doh_ips)
[ $ok -eq 0 ] || { echo "ERROR: no pude consultar Service"; exit 2; }

python - <<'PY'
import json,os
j=json.load(open("/tmp/p12-svc.json"))
print("== SERVICE ==")
print("id:", j.get("id"))
print("type:", j.get("type"))
print("name:", j.get("name"))
print("url:", j.get("url"))
print("repo:", j.get("repo"))
print("branch:", j.get("branch"))
PY
