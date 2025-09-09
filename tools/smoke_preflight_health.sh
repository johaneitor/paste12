#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }
echo "== HEALTH =="; curl -sS -i "$BASE/api/health" | sed -n '1,20p'
echo "== OPTIONS /api/notes =="; curl -sS -i -X OPTIONS "$BASE/api/notes" -H 'Origin: https://example.com' -H 'Access-Control-Request-Method: POST' | sed -n '1,40p'
