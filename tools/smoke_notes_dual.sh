#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
_red(){ printf "\033[31m%s\033[0m\n" "$*"; }; _grn(){ printf "\033[32m%s\033[0m\n" "$*"; }

echo "== smoke_notes_dual @ $BASE =="

echo "-- GET /api/notes --"
code_api="$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/api/notes")"
echo "status /api/notes = $code_api"
[[ "$code_api" == "200" ]] && _grn "OK /api/notes" || _red "NO /api/notes"

echo "-- GET /notes --"
code_no="$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/notes")"
echo "status /notes = $code_no"
[[ "$code_no" == "200" ]] && _grn "OK /notes (sin prefijo!)" || echo "NO /notes"

echo
if [[ "$code_api" != "200" && "$code_no" == "200" ]]; then
  _red "El blueprint parecería registrado SIN url_prefix (rutas en /notes)."
elif [[ "$code_api" == "200" && "$code_no" != "200" ]]; then
  _grn "El blueprint parecería con url_prefix=/api (rutas correctas en /api/notes)."
else
  echo "Ambos respondieron o ambos fallaron — ver dump de reglas."
fi
