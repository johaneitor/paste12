#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR]}"
OUTDIR="${2:-/sdcard/Download}"
API_KEY="${RENDER_API_KEY:?export RENDER_API_KEY=...}"
SERVICE_ID="${RENDER_SERVICE_ID:?export RENDER_SERVICE_ID=srv_...}"
HOST="api.render.com"; PORT="443"

# a) Crear deploy
create_deploy(){
  local url="https://${HOST}/v1/services/${SERVICE_ID}/deploys"
  for ip in $(curl -sS -H 'accept: application/dns-json' "https://1.1.1.1/dns-query?name=${HOST}&type=A" \
              | sed -n 's/.*"data":"\([0-9]\{1,3\}\(\.[0-9]\{1,3\}\)\{3\}\)".*/\1/p'); do
    curl -sS --resolve "${HOST}:${PORT}:${ip}" -X POST \
      -H "Authorization: Bearer ${API_KEY}" -H "Content-Type: application/json" \
      -d '{}' "$url" && return 0
  done
  return 1
}

# b) Esperar a que el HTML refleje HEAD
watch_html(){
  tools/deploy_watch_until_v7.sh "$BASE" 900
}

# c) Auditorías
audits(){
  tools/audit_remote_deep_v4.sh "$BASE" "$OUTDIR" >/dev/null || true
  tools/live_vs_local_v1.sh     "$BASE" "$OUTDIR" >/dev/null || true
  tools/audit_full_stack_v3.sh  "$BASE" "$OUTDIR" >/dev/null || true
}

echo "== API: crear deploy =="
create_deploy || { echo "ERROR: no pude crear el deploy via API"; exit 2; }
echo "OK: deploy creado"

echo "== Watch remoto==local =="
watch_html

echo "== Auditorías =="
audits
echo "Listo. Artefactos en $OUTDIR"
