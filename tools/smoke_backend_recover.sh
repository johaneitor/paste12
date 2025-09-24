#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
_red(){ printf "\033[31m%s\033[0m\n" "$*"; }
_grn(){ printf "\033[32m%s\033[0m\n" "$*"; }

echo "== smoke_backend_recover @ $BASE =="

echo "-- /api/health --"
curl -sS "$BASE/api/health" | python -m json.tool >/dev/null || { _red "FAIL /api/health"; exit 1; }
echo "ok"

echo "-- __api_import_error (404 esperado) --"
code="$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/__api_import_error" || true)"
[[ "$code" == "404" ]] || { _red "FAIL __api_import_error=$code"; exit 1; }
echo "ok"

echo "-- /api/_routes contiene endpoints de notas --"
R="$(curl -sS "$BASE/api/_routes")"
echo "$R" | python -m json.tool >/dev/null 2>&1 || { _red "FAIL /api/_routes no JSON"; echo "$R" | head -c 400; exit 1; }
for need in "/api/notes" "/api/notes/<int:note_id>" "/api/notes/<int:note_id>/view" "/api/notes/<int:note_id>/like" "/api/notes/<int:note_id>/report"; do
  echo "$R" | grep -q "$need" || { _red "Falta $need en /api/_routes"; exit 1; }
done
echo "ok"

echo "-- crear + view/like/report --"
C="$(curl -sS -H 'Content-Type: application/json' --data '{"text":"smoke recover","hours":24}' "$BASE/api/notes")"
echo "$C" | python -m json.tool || true
ID="$(python - <<'PY' 2>/dev/null <<<$C
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
G="$(curl -sS "$BASE/api/notes/$ID")"
echo "$G" | python -m json.tool || true

_grn "✅ smoke_backend_recover OK (ID=$ID)"
