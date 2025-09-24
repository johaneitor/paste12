#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
echo "== smoke_load_more_min @ $BASE =="
js="$(curl -sS "$BASE/js/app.js")"
echo "$js" | grep -q 'p12SetupLoadMore' && echo "OK: firma p12SetupLoadMore" || { echo "FAIL: no firma"; exit 1; }

# Semilla mínima por si la lista es corta
curl -sS -H 'Content-Type: application/json' --data '{"text":"seed for load-more","hours":24}' "$BASE/api/notes" >/dev/null || true

# API debe responder JSON con wrap
p1="$(curl -sS "$BASE/api/notes?active_only=1&limit=2&wrap=1")"
echo "$p1" | python -m json.tool >/dev/null 2>&1 && echo "OK: API wrap responde" || { echo "FAIL: API wrap"; echo "$p1"; exit 1; }

echo "✅ listo"
