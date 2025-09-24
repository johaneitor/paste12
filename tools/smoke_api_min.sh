#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"

_red(){ printf "\033[31m%s\033[0m\n" "$*"; }
_grn(){ printf "\033[32m%s\033[0m\n" "$*"; }

echo "== smoke_api_min @ $BASE =="

echo "-- /api/health --"
curl -sS "$BASE/api/health" | python -m json.tool 2>/dev/null || { _red "health no JSON"; exit 1; }

echo "-- __api_import_error -- (404 esperado)"
code="$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/__api_import_error")"
[[ "$code" == "404" ]] || { _red "Aún hay error de import (status=$code)"; exit 1; }
_grn "ok"

echo "-- __whoami -- (debe listar 'api' y has_detail_routes=true)"
who="$(curl -sS "$BASE/__whoami")"
echo "$who" | python -m json.tool 2>/dev/null || true
echo "$who" | grep -q '"api"' || _red "WARN: blueprint 'api' no listado"
echo "$who" | grep -q '"has_detail_routes": true' || _red "WARN: has_detail_routes != true"

echo "-- /api/_routes -- (debe incluir /api/notes)"
routes="$(curl -sS "$BASE/api/_routes")"
echo "$routes" | python -m json.tool 2>/dev/null | sed -n '1,80p' || true
echo "$routes" | grep -q '/api/notes' || { _red "Faltan rutas de notas"; exit 1; }

echo "-- POST /api/notes --"
res="$(curl -sS -H 'Content-Type: application/json' --data '{"text":"diag post ok","hours":24}' "$BASE/api/notes")"
echo "$res" | python -m json.tool 2>/dev/null || echo "$res"
echo "$res" | grep -q '"ok": true' || { _red "POST /api/notes no OK"; exit 1; }

_grn "✅ OK"
