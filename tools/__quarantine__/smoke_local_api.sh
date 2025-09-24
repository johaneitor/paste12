#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-http://127.0.0.1:5000}"
echo "-- GET /api/health --"
curl -sS "$BASE/api/health" | python -m json.tool
echo "-- POST /api/notes --"
resp="$(curl -sS -H 'Content-Type: application/json' --data '{"text":"hola local","hours":24}' "$BASE/api/notes")"
echo "$resp"
id="$(python - <<'PY'
import json,sys
j=json.loads(sys.stdin.read())
print(j.get("id",""))
PY <<<"$resp")"
[[ -n "$id" ]] || { echo "FAIL: no id"; exit 1; }
echo "-- POST /api/notes/$id/view --"
curl -sS -X POST "$BASE/api/notes/$id/view" | python -m json.tool
echo "-- GET /api/notes/$id --"
curl -sS "$BASE/api/notes/$id" | python -m json.tool
