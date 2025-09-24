#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-http://localhost:5000}"
_red(){ printf "\033[31m%s\033[0m\n" "$*"; }; _grn(){ printf "\033[32m%s\033[0m\n" "$*"; }

echo "== smoke_ping_diag @ $BASE =="

echo "-- /api/health --"
curl -sS "$BASE/api/health" | python -m json.tool >/dev/null && _grn "ok /api/health" || { _red "FAIL /api/health"; exit 1; }

echo "-- /api/ping --"
if curl -sS "$BASE/api/ping" | python -m json.tool >/dev/null 2>&1; then
  _grn "ok /api/ping"
else
  _red "FAIL /api/ping (cuerpo abajo si hay):"
  curl -sS "$BASE/api/ping" | head -c 400 || true
  echo
fi

echo
echo "-- /api/_routes (buscando /api/ping) --"
if curl -sS "$BASE/api/_routes" | python -m json.tool >/dev/null 2>&1; then
  curl -sS "$BASE/api/_routes" \
  | python -m json.tool \
  | sed -n 's/.*"rule": "\(.*\)".*/\1/p' \
  | sort \
  | grep -x "/api/ping" >/dev/null && _grn "ping aparece en el mapa de rutas" || _red "ping NO aparece en el mapa de rutas"
else
  _red "/api/_routes no devolvió JSON"
fi
