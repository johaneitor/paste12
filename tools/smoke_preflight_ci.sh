#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }

echo "== /api/health =="
curl -sS -i "$BASE/api/health" | sed -n '1,40p'; echo

echo "== OPTIONS /api/notes (CORS) =="
CODES="$(curl -sS -o /dev/null -w '%{http_code}' -X OPTIONS \
  -H 'Origin: https://example.com' \
  -H 'Access-Control-Request-Method: POST' \
  "$BASE/api/notes")"
if [ "$CODES" != "204" ]; then
  echo "✗ preflight no devolvió 204 (fue $CODES)"; exit 1
fi
curl -sS -i -X OPTIONS "$BASE/api/notes" \
  -H 'Origin: https://example.com' \
  -H 'Access-Control-Request-Method: POST' | sed -n '1,80p'; echo

echo "== Crear nota + like =="
ID="$(printf '{"text":"ci smoke %s abcdefghij"}' "$(date -u +%H:%M:%SZ)" \
  | curl -fsS -H 'Content-Type: application/json' --data-binary @- "$BASE/api/notes" \
  | { command -v jq >/dev/null && jq -r '.item.id // .id // empty' || cat; })"
echo "id=$ID"
[ -n "$ID" ] || { echo "✗ no se pudo crear nota"; exit 1; }
curl -sS -X POST "$BASE/api/notes/$ID/like" | { command -v jq >/dev/null && jq -r '.' || cat; }; echo

echo "== Paginación (limit=3) =="
curl -sS -i "$BASE/api/notes?limit=3" | sed -n '1,120p'
