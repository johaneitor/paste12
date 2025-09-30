#!/usr/bin/env bash
set -euo pipefail
SERVICE_ID="${1:?Uso: $0 srv-XXXXXXXX}"
curl -fsS -H "Authorization: Bearer ${RENDER_API_KEY:?Falta RENDER_API_KEY}" \
  "https://api.render.com/v1/services/${SERVICE_ID}/deploys?limit=5" \
| python - <<'PY'
import sys,json
d=json.load(sys.stdin)
for x in d:
  print(f"{x.get('id')} | {x.get('status')} | commit={x.get('commitId')} | createdAt={x.get('createdAt')}")
PY
