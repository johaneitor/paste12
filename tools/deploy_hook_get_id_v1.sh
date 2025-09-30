#!/usr/bin/env bash
set -euo pipefail
HOOK="${RENDER_DEPLOY_HOOK:?Uso: export RENDER_DEPLOY_HOOK=https://api.render.com/deploy/srv-...?...}"
HOST="api.render.com"; PORT="443"

doh_ips(){ for u in \
 "https://1.1.1.1/dns-query?name=${HOST}&type=A" \
 "https://1.0.0.1/dns-query?name=${HOST}&type=A"
do curl -sS -H 'accept: application/dns-json' "$u" \
 | grep -oE '"data":"([0-9]{1,3}\.){3}[0-9]{1,3}"' \
 | cut -d':' -f2 | tr -d '"'; done | sort -u; }

resp=""
for ip in $(doh_ips); do
  if resp="$(curl -sS -i --resolve "${HOST}:${PORT}:${ip}" -X POST "$HOOK")"; then
    break
  fi
done

# Mostrar respuesta y extraer deploy_id
echo "$resp" | sed -n '1,20p' >&2
echo "$resp" | awk 'BEGIN{p=0} /^$/{p=1;next} p{print}' \
| python - <<'PY'
import sys,json
try:
  j=json.load(sys.stdin)
  did=j.get("deploy",{}).get("id")
  if not did: raise SystemExit(1)
  print(did)
except Exception:
  raise SystemExit(2)
PY
