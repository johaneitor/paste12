#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"
LIMIT="${LIMIT:-20}"
if [ -z "$BASE" ]; then
  echo "Uso: $0 https://tu-app.onrender.com" >&2
  exit 1
fi

json="$(curl -fsS "$BASE/api/notes?limit=$LIMIT")"

python - <<'PY'
import sys, json
data = sys.stdin.read()
try:
    arr = json.loads(data)
    total = len(arr) if isinstance(arr, list) else 0
    with_reports = sum(1 for x in arr if isinstance(x, dict) and int(x.get("reports",0))>0)
    print(f"Total: {total}")
    print(f"Con reportes: {with_reports}")
except Exception as e:
    print("Error parseando JSON:", e, file=sys.stderr)
    sys.exit(1)
PY <<<"$json"
