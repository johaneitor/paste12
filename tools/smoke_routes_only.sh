#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
_red(){ printf "\033[31m%s\033[0m\n" "$*"; }
_grn(){ printf "\033[32m%s\033[0m\n" "$*"; }

echo "== smoke_routes_only @ $BASE =="

# 1) health
curl -sS "$BASE/api/health" | python -m json.tool >/dev/null || { _red "FAIL /api/health"; exit 1; }
echo "ok /api/health"

# 2) esperar a que no haya error de import
for i in $(seq 1 40); do
  c="$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/__api_import_error" || true)"
  [[ "$c" == "404" ]] && break
  sleep 2
done
[[ "$c" == "404" ]] || { _red "__api_import_error=$c (debe ser 404)"; exit 1; }

# 3) /api/_routes
R="$(curl -sS "$BASE/api/_routes" || true)"
echo "$R" | python -m json.tool >/dev/null 2>&1 || { _red "FAIL /api/_routes no JSON"; echo "$R" | head -c 400; echo; exit 1; }

# 4) aseguramos que aparezcan las rutas clave
need=( "/api/notes" "/api/notes/<int:note_id>" "/api/notes/<int:note_id>/view" "/api/notes/<int:note_id>/like" "/api/notes/<int:note_id>/report" )
ok=1
for n in "${need[@]}"; do
  echo "$R" | grep -q "\"rule\": \"$n\"" || { _red "Falta $n"; ok=0; }
done
[[ $ok == 1 ]] || exit 1

_grn "✅ OK /api/_routes y rutas CRUD presentes"
