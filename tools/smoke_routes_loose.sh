#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
_red(){ printf "\033[31m%s\033[0m\n" "$*"; }
_grn(){ printf "\033[32m%s\033[0m\n" "$*"; }

echo "== smoke_routes_loose @ $BASE =="

curl -sS "$BASE/api/health" | python -m json.tool >/dev/null || { _red "FAIL /api/health"; exit 1; }
echo "ok /api/health"

# Esperar import sano
for i in $(seq 1 40); do
  c="$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/__api_import_error" || true)"
  [[ "$c" == "404" ]] && break
  sleep 2
done
echo "__api_import_error=$c"

# ping
P="$(curl -sS "$BASE/api/ping" || true)"
if echo "$P" | python -m json.tool >/dev/null 2>&1; then
  echo "ok /api/ping"
else
  echo "WARN /api/ping no JSON o 404:"
  echo "$P" | head -c 240; echo
fi

# rutas
R="$(curl -sS "$BASE/api/_routes" || true)"
if ! echo "$R" | python -m json.tool >/dev/null 2>&1; then
  echo "fallback /api/routes"
  R="$(curl -sS "$BASE/api/routes" || true)"
fi
if echo "$R" | python -m json.tool >/dev/null 2>&1; then
  echo "ok dump rutas"
else
  _red "FAIL rutas (no JSON)"
  echo "$R" | head -c 400; echo
  echo "-- __whoami --"
  curl -sS "$BASE/__whoami" | python -m json.tool || true
  exit 1
fi

# Verificar presencia de CRUD clave si hay dump
for need in "/api/notes" "/api/notes/<int:note_id>" "/api/notes/<int:note_id>/view" "/api/notes/<int:note_id>/like" "/api/notes/<int:note_id>/report"; do
  echo "$R" | grep -q "\"rule\": \"$need\"" || echo "WARN falta $need"
done

_grn "Terminado."
