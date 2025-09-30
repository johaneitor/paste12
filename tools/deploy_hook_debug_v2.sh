#!/usr/bin/env bash
set -euo pipefail
HOOK="${RENDER_DEPLOY_HOOK:?Uso: export RENDER_DEPLOY_HOOK='https://api.render.com/deploy/srv-...?...'}"
HOST="api.render.com"; PORT="443"

doh_ips(){
  # Devuelve 1 IP por línea (únicas), sin duplicar ni concatenar
  for u in \
    "https://1.1.1.1/dns-query?name=${HOST}&type=A" \
    "https://1.0.0.1/dns-query?name=${HOST}&type=A"
  do
    curl -sS -H 'accept: application/dns-json' "$u" \
    | grep -oE '"data":"([0-9]{1,3}\.){3}[0-9]{1,3}"' \
    | cut -d':' -f2 | tr -d '"' 
  done | sort -u
}

ips="$(doh_ips)"
[ -n "$ips" ] || { echo "No pude resolver $HOST via DoH"; exit 2; }

echo "HOOK: $HOOK"
while IFS= read -r ip; do
  echo "== Try $ip =="
  curl -sS -i --resolve "${HOST}:${PORT}:${ip}" -X POST "$HOOK" || true
  echo
done <<< "$ips"
