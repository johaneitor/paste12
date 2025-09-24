#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
_red(){ printf "\033[31m%s\033[0m\n" "$*"; }; _grn(){ printf "\033[32m%s\033[0m\n" "$*"; }

echo "== smoke_after_fix_prefix @ $BASE =="

curl -sS "$BASE/api/health" | python -m json.tool >/dev/null && _grn "ok /api/health" || { _red "FAIL /api/health"; exit 1; }

if curl -sS "$BASE/api/ping" | python -m json.tool >/dev/null 2>&1; then
  _grn "ok /api/ping"
else
  _red "FAIL /api/ping"; curl -sS "$BASE/api/ping" | head -c 300; echo
fi

if curl -sS "$BASE/api/_routes" | python -m json.tool >/dev/null 2>&1; then
  _grn "ok /api/_routes"
else
  _red "FAIL /api/_routes"; curl -sS "$BASE/api/_routes" | head -c 300; echo
fi

code_api="$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/api/notes")"
code_no="$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/notes")"
echo "status /api/notes = $code_api ; /notes = $code_no"
if [[ "$code_api" == "200" && "$code_no" != "200" ]]; then
  _grn "OK: blueprint con url_prefix=/api"
else
  _red "Aún no está con prefijo; revisar rutas."
fi
