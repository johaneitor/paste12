#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
_red(){ printf "\033[31m%s\033[0m\n" "$*"; }
_grn(){ printf "\033[32m%s\033[0m\n" "$*"; }

echo "== smoke_after_factory @ $BASE =="

echo "-- /api/health --"
curl -sS "$BASE/api/health" | python -m json.tool || { _red "FAIL /api/health"; exit 1; }

echo
echo "-- esperando __api_import_error=404 (hasta 60 x 3s) --"
ok=0
for i in $(seq 1 60); do
  code="$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/__api_import_error" || true)"
  [[ "$code" == "404" ]] && { ok=1; break; }
  printf "aún=%s  " "$code"
  sleep 3
done
echo
[[ $ok == 1 ]] || { _red "Timeout: __api_import_error no llegó a 404"; exit 1; }
_grn "ok import"

echo
echo "-- /api/_routes --"
R="$(curl -sS "$BASE/api/_routes" || true)"
echo "$R" | python -m json.tool >/dev/null 2>&1 || { _red "FAIL /api/_routes no JSON"; echo "$R" | head -c 400; echo; exit 1; }
for need in "/api/notes" "/api/notes/<int:note_id>" "/api/notes/<int:note_id>/view" "/api/notes/<int:note_id>/like" "/api/notes/<int:note_id>/report"; do
  echo "$R" | grep -q "$need" || { _red "Falta $need en /api/_routes"; exit 1; }
done
_grn "ok rutas"

echo
echo "-- CRUD --"
C="$(curl -sS -H 'Content-Type: application/json' --data '{"text":"smoke ok","hours":24}' "$BASE/api/notes")"
ID="$(python - <<'PY' <<<"$C" 2>/dev/null
import sys,json
try:
  j=json.loads(sys.stdin.read()); print(j.get("id",""))
except: print("")
PY
)"
[[ -n "$ID" ]] || { _red "FAIL create"; echo "$C"; exit 1; }

curl -sS -X POST "$BASE/api/notes/$ID/view"   | python -m json.tool || true
curl -sS -X POST "$BASE/api/notes/$ID/like"   | python -m json.tool || true
curl -sS -X POST "$BASE/api/notes/$ID/report" | python -m json.tool || true
curl -sS "$BASE/api/notes/$ID" | python -m json.tool || true

_grn "✅ smoke_after_factory OK (ID=$ID)"
