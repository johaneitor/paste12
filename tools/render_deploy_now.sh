#!/usr/bin/env bash
set -euo pipefail
: "${RENDER_API_KEY:?export RENDER_API_KEY=...}"
: "${RENDER_SERVICE_ID:?export RENDER_SERVICE_ID=...}"
curl -fsS -X POST \
  -H "Authorization: Bearer $RENDER_API_KEY" \
  -H "Content-Type: application/json" \
  "https://api.render.com/v1/services/$RENDER_SERVICE_ID/deploys" \
  -d '{"clearCache":true}' | jq .
