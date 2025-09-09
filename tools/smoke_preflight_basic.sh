#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }
echo "== /api/health =="; curl -sS -i "$BASE/api/health" | sed -n '1,40p'; echo
echo "== OPTIONS /api/notes (CORS) =="
curl -sS -i -X OPTIONS "$BASE/api/notes" \
  -H 'Origin: https://example.com' \
  -H 'Access-Control-Request-Method: POST' | sed -n '1,80p'; echo
echo "== Crear nota + like (best-effort) =="
ID="$(printf '{"text":"smoke preflight %s 1234567890"}' "$(date -u +%H:%M:%SZ)" \
  | curl -fsS -H 'Content-Type: application/json' --data-binary @- "$BASE/api/notes" \
  | { command -v jq >/dev/null && jq -r '.item.id // .id // empty' || cat; })"
echo "id=$ID"
if [ -n "$ID" ]; then
  curl -sS -X POST "$BASE/api/notes/$ID/like" | { command -v jq >/dev/null && jq -r '.' || cat; }
fi
