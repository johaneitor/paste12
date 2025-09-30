#!/usr/bin/env bash
set -euo pipefail
DEP="${1:?Uso: $0 dep-XXXXXXXXXXXX}"
: "${RENDER_API_KEY:?export RENDER_API_KEY=rnd_...}"
HOST="api.render.com"; PORT="443"
URL="https://${HOST}/v1/deploys/${DEP}"

doh_ips(){ for u in \
 "https://1.1.1.1/dns-query?name=${HOST}&type=A" \
 "https://1.0.0.1/dns-query?name=${HOST}&type=A"
do curl -sS -H 'accept: application/dns-json' "$u" \
 | grep -oE '"data":"([0-9]{1,3}\.){3}[0-9]{1,3}"' \
 | cut -d':' -f2 | tr -d '"'; done | sort -u; }

json=""
for ip in $(doh_ips); do
  if json="$(curl -sS --resolve "${HOST}:${PORT}:${ip}" \
      -H "Authorization: Bearer ${RENDER_API_KEY}" -H "Accept: application/json" "$URL")"; then
    break
  fi
done
[ -n "$json" ] || { echo "ERROR: no pude consultar deploy $DEP" >&2; exit 2; }

python - <<'PY' <<<"$json"
import sys,json
j=json.load(sys.stdin)
print("deployId:", j.get("id"))
print("status  :", j.get("status"))
print("service :", j.get("serviceId"))
print("commit  :", j.get("commitId"))
print("created :", j.get("createdAt"))
PY
