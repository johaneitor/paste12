#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-http://localhost:5000}"

echo "== smoke_share_report @ $BASE =="
echo "-- create --"
RES=$(curl -sS -H 'Content-Type: application/json' --data '{"text":"share/report smoke","hours":24}' "$BASE/api/notes")
echo "$RES"
ID=$(python - <<'PY'
import sys, json; print(json.load(sys.stdin)['id'])
PY <<<"$RES")
echo "ID=$ID"

echo "-- report --"
curl -sS -X POST "$BASE/api/notes/$ID/report" | python -m json.tool

echo "-- get (should show reports>=1) --"
curl -sS "$BASE/api/notes/$ID" | python -m json.tool
