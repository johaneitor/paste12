#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; MAX="${2:-100}"
[ -n "$BASE" ] || { echo "uso: $0 https://host [max_items_cap]"; exit 2; }

echo "== /api/health =="
curl -sS -i "$BASE/api/health" | sed -n '1,40p' | sed 's/\r$//'
echo

echo "== OPTIONS /api/notes (CORS) =="
curl -sS -i -X OPTIONS "$BASE/api/notes" \
  -H 'Origin: https://example.com' \
  -H 'Access-Control-Request-Method: POST' | sed -n '1,120p' | sed 's/\r$//'
echo

echo "== ACAO en 404 (debe estar si hay Origin) =="
curl -sS -i "$BASE/api/nope" -H 'Origin: https://example.com' | sed -n '1,40p' | sed 's/\r$//'
echo

echo "== Cap de limit (<= $MAX) =="
if command -v jq >/dev/null 2>&1; then
  N="$(curl -sS "$BASE/api/notes?limit=999999" | jq -r '.items|length')"
else
  N="$(curl -sS "$BASE/api/notes?limit=999999" | tr -cd '['','| awk -F, '{print NF-1}')"
fi
echo "items devueltos: $N (esperado: <= $MAX)"
if [ "${N:-0}" -le "$MAX" ]; then
  echo "✓ cap OK"
else
  echo "✗ cap roto"; exit 1
fi
