#!/usr/bin/env bash
set -euo pipefail
: "${RENDER_API_KEY:?RENDER_API_KEY no seteada}"
: "${RENDER_SERVICE_ID:?RENDER_SERVICE_ID no seteado}"
curl -fsS \
  -H "Authorization: Bearer ${RENDER_API_KEY}" \
  "https://api.render.com/v1/services/${RENDER_SERVICE_ID}/deploys?limit=1"
echo
