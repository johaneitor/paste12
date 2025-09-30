#!/usr/bin/env bash
set -euo pipefail
API_KEY="${RENDER_API_KEY:?Uso: export RENDER_API_KEY=...}"
SERVICE_ID="${RENDER_SERVICE_ID:?Uso: export RENDER_SERVICE_ID=srv_...}"
HOST="api.render.com"; PORT="443"
URL="https://${HOST}/v1/services/${SERVICE_ID}/deploys?limit=5"

doh(){
  for u in \
    "https://1.1.1.1/dns-query?name=${HOST}&type=A" \
    "https://1.0.0.1/dns-query?name=${HOST}&type=A"
  do
    curl -sS -H 'accept: application/dns-json' "$u" \
    | sed -n 's/.*"data":"\([0-9]\{1,3\}\(\.[0-9]\{1,3\}\)\{3\}\)".*/\1/p'
  done
}
ips="$(doh | sort -u)"
[ -n "$ips" ] || { echo "No pude resolver $HOST via DoH"; exit 2; }

tmp="$(mktemp)"
ok=false
for ip in $ips; do
  if curl -sS --resolve "${HOST}:${PORT}:${ip}" \
      -H "Authorization: Bearer ${API_KEY}" -H "Accept: application/json" "$URL" -o "$tmp"; then
    ok=true; break
  fi
done
$ok || { echo "ERROR: no pude consultar la API"; exit 3; }

python - <<'PY'
import json,sys
j=json.load(open(sys.argv[1]))
for d in j:
  print(f"id={d.get('id')} status={d.get('status')} commit={d.get('commitId')} createdAt={d.get('createdAt')}")
PY
"$tmp"
rm -f "$tmp"
