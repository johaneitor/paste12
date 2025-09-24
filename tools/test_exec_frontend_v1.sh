#!/usr/bin/env bash
set -euo pipefail

BASE="${1:-https://paste12-rmsk.onrender.com}"

echo "== FRONTEND EXEC v1 =="
# Sonda index
bash tools/test_frontend_adsense.sh "$BASE"

# Sonda mínima FE↔BE: lista inicial (no falla si backend devuelve JSON válido)
echo "== FE↔BE GET /api/notes =="
curl -fsS -H 'Accept: application/json' "$BASE/api/notes?limit=3" | head -c 200 | tr -d '\n'
echo
echo "✔ FE↔BE básico OK"
