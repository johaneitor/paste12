#!/usr/bin/env bash
set -euo pipefail
BASE="https://paste12-rmsk.onrender.com"

echo "→ BASE=$BASE"
echo "== health =="
curl -sS -i "$BASE/api/health" || true
echo
echo "== create (JSON) =="
curl -sS -i -H "Content-Type: application/json" \
  -d '{"text":"hola render JSON","hours":24}' "$BASE/api/notes" || true
echo
echo "== create (form-data) =="
curl -sS -i -X POST -F 'text=hola render form' -F 'hours=24' "$BASE/api/notes" || true
echo
echo "== create (x-www-form-urlencoded) =="
curl -sS -i -X POST -H "Content-Type: application/x-www-form-urlencoded" \
  --data 'text=hola render urlencode&hours=24' "$BASE/api/notes" || true
echo
echo "== list =="
curl -sS "$BASE/api/notes" | python -m json.tool || true
