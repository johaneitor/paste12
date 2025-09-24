#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
ts="$(date -u +%Y%m%d-%H%M%SZ)"

echo "== Smoke v13 ($BASE) =="

# health
curl -fsS "$BASE/api/health" | python - <<'PY'
import sys, json
data=json.load(sys.stdin)
assert data.get("ok") is True
print("OK  - health")
PY

# OPTIONS CORS
curl -i -s -X OPTIONS "$BASE/api/notes" | tee /dev/stderr | awk 'BEGIN{ok=0}/^HTTP/{c=$2} END{exit c!=204}'
echo "OK  - OPTIONS 204"

# GET with headers (should not be 500)
hdrs="$(curl -s -D - "$BASE/api/notes?limit=5" -o /dev/null)"
echo "$hdrs" | grep -qi '^HTTP/.* 200' && echo "OK  - GET 200" || (echo "$hdrs" && exit 1)
echo "$hdrs" | grep -qi '^content-type: application/json' && echo "OK  - CT json" || (echo "FAIL CT"; exit 1)
echo "$hdrs" | grep -qi '^link: .*rel="next"' && echo "OK  - Link next" || echo "WARN- Link next ausente (tolerado)"

# POST JSON (shim/real)
curl -fsS -H 'Content-Type: application/json' -d '{"text":"contract v13 json 123"}' "$BASE/api/notes" >/dev/null && echo "OK  - POST json"

# POST FORM
curl -fsS -F 'text=contract v13 form 123' "$BASE/api/notes" >/dev/null && echo "OK  - POST form"

echo "== FIN =="
