#!/usr/bin/env bash
set -euo pipefail
SERVICE_ID="${1:?Uso: $0 srv-XXXXXXXX}"
curl -fsS -X PATCH \
  -H "Authorization: Bearer ${RENDER_API_KEY:?Falta RENDER_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"autoDeploy":true,"branch":"main"}' \
  "https://api.render.com/v1/services/${SERVICE_ID}" >/dev/null
echo "OK: autoDeploy=true branch=main en ${SERVICE_ID}"
