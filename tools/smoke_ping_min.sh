#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-http://localhost:5000}"
_red(){ printf "\033[31m%s\033[0m\n" "$*"; }; _grn(){ printf "\033[32m%s\033[0m\n" "$*"; }

echo "== smoke_ping_min @ $BASE =="
echo "-- /api/health --"
curl -sS "$BASE/api/health" | python -m json.tool >/dev/null && _grn "ok /api/health" || { _red "FAIL /api/health"; exit 1; }

echo "-- /api/ping --"
curl -sS "$BASE/api/ping" | python -m json.tool >/dev/null && _grn "ok /api/ping" || { _red "FAIL /api/ping"; exit 1; }

echo "-- /api/_routes --"
R="$(curl -sS "$BASE/api/_routes" || true)"
echo "$R" | python -m json.tool >/dev/null 2>&1 || { _red "WARN /api/_routes no JSON"; echo "$R" | head -c 400; echo; exit 0; }
echo "$R" | grep -q '"rule": "/api/ping"' && _grn "ok /api/_routes muestra /api/ping" || _red "WARN: /api/ping no listado en _routes"
