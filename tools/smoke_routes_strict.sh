#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
_red(){ printf "\033[31m%s\033[0m\n" "$*"; }
_grn(){ printf "\033[32m%s\033[0m\n" "$*"; }

echo "== smoke_routes_strict @ $BASE =="

# 1) health
curl -sS "$BASE/api/health" | python -m json.tool >/dev/null || { _red "FAIL /api/health"; exit 1; }
echo "ok /api/health"

# 2) import sano
for i in $(seq 1 40); do
  c="$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/__api_import_error" || true)"
  [[ "$c" == "404" ]] && break
  sleep 2
done
[[ "$c" == "404" ]] || { _red "__api_import_error=$c (debe ser 404)"; exit 1; }

# 3) ping
P="$(curl -sS "$BASE/api/ping" || true)"
echo "$P" | python -m json.tool >/dev/null 2>&1 || { _red "FAIL /api/ping"; echo "$P" | head -c 400; echo; exit 1; }
echo "ok /api/ping"

# 4) _routes o fallback routes
R="$(curl -sS "$BASE/api/_routes" || true)"
if ! echo "$R" | python -m json.tool >/dev/null 2>&1; then
  echo "fallback /api/routes"
  R="$(curl -sS "$BASE/api/routes" || true)"
fi
echo "$R" | python -m json.tool >/dev/null 2>&1 || { _red "FAIL /api/_routes y /api/routes no JSON"; echo "$R" | head -c 400; echo;
  echo "-- /__whoami --"
  curl -sS "$BASE/__whoami" | python -m json.tool || true
  exit 1; }

need=( "/api/notes" "/api/notes/<int:note_id>" "/api/notes/<int:note_id>/view" "/api/notes/<int:note_id>/like" "/api/notes/<int:note_id>/report" )
ok=1
for n in "${need[@]}"; do
  echo "$R" | grep -q "\"rule\": \"$n\"" || { _red "Falta $n"; ok=0; }
done
[[ $ok == 1 ]] || exit 1

_grn "✅ OK rutas de introspección y CRUD presentes"
