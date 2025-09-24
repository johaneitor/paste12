#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-http://localhost:5000}"

echo "== __version =="
curl -sS "$BASE/__version" | python -m json.tool || echo "(sin JSON)"

echo
echo "== /api/_routes (primeras 30 reglas) =="
curl -sS "$BASE/api/_routes" | python -m json.tool 2>/dev/null \
  | sed -n 's/.*"rule": "\(.*\)".*/\1/p' | head -n 30 || cat
