#!/usr/bin/env bash
set -euo pipefail
: "${RENDER_API_KEY:?RENDER_API_KEY no seteada}"
: "${RENDER_SERVICE_ID:?RENDER_SERVICE_ID no seteado}"
CLEAR="${1:-true}"
out="$(mktemp)"
code="$(curl -sS -o "$out" -w "%{http_code}" \
  -H "Authorization: Bearer ${RENDER_API_KEY}" \
  -H "Content-Type: application/json" \
  -X POST "https://api.render.com/v1/services/${RENDER_SERVICE_ID}/deploys" \
  -d "{\"clearCache\": ${CLEAR}}")" || { rc=$?; echo "curl failed rc=$rc"; cat "$out"; exit $rc; }
echo "HTTP $code"
cat "$out"
echo
[[ "$code" =~ ^2 ]] || exit 1
