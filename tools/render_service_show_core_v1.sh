#!/usr/bin/env bash
set -euo pipefail
SERVICE_ID="${1:?Uso: $0 srv-XXXXXXXX}"
curl -fsS -H "Authorization: Bearer ${RENDER_API_KEY:?Falta RENDER_API_KEY}" \
  "https://api.render.com/v1/services/${SERVICE_ID}" \
| python - <<'PY'
import sys,json
try:
  d=json.load(sys.stdin)
  s=d.get('service', d)
  print("id:", s.get('id'))
  print("type:", s.get('type'))
  print("url:", s.get('serviceDetails',{}).get('url'))
  print("repo:", s.get('repo'))
  print("branch:", s.get('branch'))
  print("autoDeploy:", s.get('autoDeploy'))
except Exception as e:
  print("ERROR:", e)
  sys.exit(2)
PY
