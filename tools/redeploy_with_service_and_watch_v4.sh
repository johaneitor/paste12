#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL srv-XXXXXXXX [OUTDIR] }"
SERVICE_ID="${2:?Uso: $0 BASE_URL srv-XXXXXXXX [OUTDIR] }"
OUTDIR="${3:-/sdcard/Download}"
: "${RENDER_API_KEY:?export RENDER_API_KEY=rnd_...}"
HOST="api.render.com"; PORT="443"
URL="https://${HOST}/v1/services/${SERVICE_ID}/deploys"

sent=0
while IFS= read -r ip; do
  code="$(curl -sS --resolve "${HOST}:${PORT}:${ip}" -o /dev/null -w '%{http_code}' \
    -X POST -H "Authorization: Bearer ${RENDER_API_KEY}" \
    -H "Content-Type: application/json" -d '{}' "$URL" || true)"
  if [[ "$code" =~ ^2 ]]; then
    echo "HTTP $code via $ip"
    sent=1; break
  fi
done < <(tools/p12_doh_ips_v1.sh "$HOST")
[ "$sent" = "1" ] || { echo "ERROR: no pude crear deploy via API (serviceId=$SERVICE_ID)"; exit 2; }

echo "OK: deploy creado"
tools/deploy_watch_until_v7.sh "$BASE" 900
tools/audit_remote_deep_v4.sh "$BASE" "$OUTDIR" >/dev/null || true
tools/live_vs_local_v1.sh     "$BASE" "$OUTDIR" >/dev/null || true
tools/audit_full_stack_v3.sh  "$BASE" "$OUTDIR" >/dev/null || true
echo "Listo. Artefactos en $OUTDIR"
