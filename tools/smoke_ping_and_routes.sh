#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
_red(){ printf "\033[31m%s\033[0m\n" "$*"; }; _grn(){ printf "\033[32m%s\033[0m\n" "$*"; }

echo "== smoke_ping_and_routes @ $BASE =="

echo "-- /api/health --"
curl -sS "$BASE/api/health" | python -m json.tool >/dev/null && _grn "ok /api/health" || _red "FAIL /api/health"

echo "-- /api/ping --"
if curl -sS "$BASE/api/ping" | python -m json.tool >/dev/null 2>&1; then
  _grn "ok /api/ping"
else
  _red "FAIL /api/ping (body abajo):"
  curl -sS "$BASE/api/ping" | head -c 400; echo
fi

echo "-- /api/_routes --"
if curl -sS "$BASE/api/_routes" | python -m json.tool >/dev/null 2>&1; then
  _grn "ok /api/_routes (JSON)"
  curl -sS "$BASE/api/_routes" | python -m json.tool \
    | sed -n 's/.*"rule": "\(.*\)".*/\1/p' | sort | sed -n '1,40p'
else
  _red "FAIL /api/_routes (no JSON / 404)"
  curl -sS "$BASE/api/_routes" | head -c 400; echo
fi
