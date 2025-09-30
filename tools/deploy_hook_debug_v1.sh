#!/usr/bin/env bash
set -euo pipefail
HOOK="${RENDER_DEPLOY_HOOK:?Uso: export RENDER_DEPLOY_HOOK='https://api.render.com/deploy/srv-...?...'}"
HOST="api.render.com"; PORT="443"

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

for ip in $ips; do
  echo "== Try ${ip} =="
  curl -sS -i --resolve "${HOST}:${PORT}:${ip}" -X POST "$HOOK" || true
  echo
done
