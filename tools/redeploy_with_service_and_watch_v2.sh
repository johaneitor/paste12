#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL srv-XXXXXXXX [OUTDIR] }"
SERVICE_ID="${2:?Uso: $0 BASE_URL srv-XXXXXXXX [OUTDIR] }"
OUTDIR="${3:-/sdcard/Download}"
: "${RENDER_API_KEY:?export RENDER_API_KEY=rnd_...}"
HOST="api.render.com"; PORT="443"
URL="https://${HOST}/v1/services/${SERVICE_ID}/deploys"

doh_ips(){ for u in "https://1.1.1.1/dns-query?name=${HOST}&type=A" "https://1.0.0.1/dns-query?name=${HOST}&type=A"; do
  curl -sS -H 'accept: application/dns-json' "$u" | grep -oE '"data":"([0-9]{1,3}\.){3}[0-9]{1,3}"' | cut -d':' -f2 | tr -d '"'
done | sort -u; }

code=000
for ip in $(doh_ips); do
  code="$(curl -sS --resolve "${HOST}:${PORT}:${ip}" -o /dev/null -w '%{http_code}' \
    -X POST -H "Authorization: Bearer ${RENDER_API_KEY}" -H "Content-Type: application/json" -d '{}' "$URL" || true)"
  [[ "$code" =~ ^2 ]] && { echo "HTTP $code via $ip"; break; }
done
[[ "$code" =~ ^2 ]] || { echo "ERROR: no pude crear deploy via API (serviceId=$SERVICE_ID)"; exit 2; }
echo "OK: deploy creado"

tools/deploy_watch_until_v7.sh "$BASE" 900
tools/audit_remote_deep_v4.sh "$BASE" "$OUTDIR" >/dev/null || true
tools/live_vs_local_v1.sh     "$BASE" "$OUTDIR" >/dev/null || true
tools/audit_full_stack_v3.sh  "$BASE" "$OUTDIR" >/dev/null || true
echo "Listo. Artefactos en $OUTDIR"
