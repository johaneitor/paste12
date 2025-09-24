#!/usr/bin/env bash
set -euo pipefail
: "${RENDER_API_KEY:?RENDER_API_KEY no seteada}"
: "${RENDER_SERVICE_ID:?RENDER_SERVICE_ID no seteado}"
json="$(curl -fsS -H "Authorization: Bearer ${RENDER_API_KEY}" "https://api.render.com/v1/services/${RENDER_SERVICE_ID}")"
python - <<'PY' <<<"$json"
import sys, json
s=json.load(sys.stdin)
svc=s.get("service",{})
print("name=", svc.get("name"))
print("type=", svc.get("type"))
print("branch=", svc.get("gitBranch"))
print("autoDeploy=", svc.get("autoDeploy"))
PY
