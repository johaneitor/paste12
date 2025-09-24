#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"

_red(){ printf "\033[31m%s\033[0m\n" "$*"; }
_grn(){ printf "\033[32m%s\033[0m\n" "$*"; }
_yel(){ printf "\033[33m%s\033[0m\n" "$*"; }

echo "== run_system_smoke @ $BASE =="

echo "-- /api/health --"
curl -sS "$BASE/api/health" | python -m json.tool || { _red "FAIL /api/health"; exit 1; }
echo

# 1) Inspect __api_import_error
echo "-- __api_import_error --"
code="$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/__api_import_error" || true)"
if [[ "$code" == "404" ]]; then
  _grn "ok (__api_import_error=404)"
else
  _yel "__api_import_error=$code (mostrando cuerpo si existe)"
  body="$(curl -sS "$BASE/__api_import_error" || true)"
  # intenta pretty JSON si corresponde
  if python - <<'PY' >/dev/null 2>&1 <<<"$body"; then
import sys,json; json.loads(sys.stdin.read()); print()
PY
    echo "$body" | python -m json.tool
  else
    echo "(no JSON; primeros 600 bytes)"; head -c 600 <<<"$body"; echo
  fi
fi
echo

# 2) Espera a 404 (hasta 60 x 3s)
if [[ "$code" != "404" ]]; then
  echo "-- Esperando a __api_import_error=404 (hasta 60 intentos cada 3s) --"
  for i in $(seq 1 60); do
    sleep 3
    code="$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/__api_import_error" || true)"
    if [[ "$code" == "404" ]]; then
      _grn "ok: __api_import_error=404"
      break
    fi
    printf "aún=%s  " "$code"
  done
  echo
  [[ "$code" == "404" ]] || { _red "Timeout esperando __api_import_error=404 (último=$code)"; exit 1; }
fi

# 3) Rutas mínimas
echo "-- /api/_routes --"
R="$(curl -sS "$BASE/api/_routes" || true)"
echo "$R" | python -m json.tool >/dev/null 2>&1 || { _red "FAIL /api/_routes no JSON"; echo "$R" | head -c 400; echo; exit 1; }
for need in "/api/notes" "/api/notes/<int:note_id>" "/api/notes/<int:note_id>/view" "/api/notes/<int:note_id>/like" "/api/notes/<int:note_id>/report"; do
  echo "$R" | grep -q "$need" || { _red "Falta $need en /api/_routes"; exit 1; }
done
_grn "ok rutas"
echo

# 4) CRUD básico
echo "-- crear + view/like/report --"
C="$(curl -sS -H 'Content-Type: application/json' --data '{"text":"smoke backend","hours":24}' "$BASE/api/notes")"
echo "$C" | python -m json.tool || true
ID="$(python - <<'PY' 2>/dev/null <<<"$C"
import json,sys
try:
  j=json.loads(sys.stdin.read()); print(j.get("id",""))
except: print("")
PY
)"
[[ -n "$ID" ]] || { _red "FAIL: no pude extraer id"; exit 1; }

curl -sS -X POST "$BASE/api/notes/$ID/view"   | python -m json.tool || true
curl -sS -X POST "$BASE/api/notes/$ID/like"   | python -m json.tool || true
curl -sS -X POST "$BASE/api/notes/$ID/report" | python -m json.tool || true
curl -sS "$BASE/api/notes/$ID" | python -m json.tool || true

_grn "✅ run_system_smoke OK (ID=$ID)"
