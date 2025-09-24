#!/usr/bin/env bash
set -u -o pipefail
BASE="${1:-}"
[ -n "$BASE" ] || { echo "Uso: $0 https://host"; exit 2; }

echo "== OPTIONS /api/notes (preflight) =="
curl -sS -i -X OPTIONS "$BASE/api/notes" \
  -H 'Origin: https://example.com' \
  -H 'Access-Control-Request-Method: POST' | sed -n '1,80p'
echo "---------------------------------------------"

echo "== GET /api/notes con Origin (CORS allow) =="
curl -sS -i "$BASE/api/notes?limit=1" -H 'Origin: https://example.com' | sed -n '1,40p'
echo "---------------------------------------------"
