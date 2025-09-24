#!/usr/bin/env bash
set -euo pipefail
: "${RENDER_API_KEY:?RENDER_API_KEY no seteada}"
curl -fsS -H "Authorization: Bearer ${RENDER_API_KEY}" "https://api.render.com/v1/services?limit=200" \
| python - <<'PY'
import sys, json
for s in json.load(sys.stdin):
  svc=s.get("service",{})
  print(f"{s.get('id')}\t{svc.get('name')}\tbranch={svc.get('gitBranch')}")
PY
