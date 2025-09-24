#!/usr/bin/env bash
set -Eeuo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"

echo "BASE=$BASE"

echo "— HEAD estáticos —"
for p in / /js/app.js /css/styles.css /robots.txt; do
  printf "  %-18s " "$p"
  code=$(curl -sS -o /dev/null -w '%{http_code}' "$BASE$p" || true)
  echo "$code"
done

echo "— Health —"
curl -sS -D- -o /dev/null "$BASE/api/health" | sed -n '1,12p'

echo "— Crear nota (JSON) —"
curl -sS -H 'Content-Type: application/json' \
  -d '{"text":"deploy smoke ok","hours":24}' \
  "$BASE/api/notes" | python -m json.tool

echo "— Listar 5 notas —"
curl -sS "$BASE/api/notes?limit=5" | python -m json.tool | sed -n '1,30p'
echo "— Cabeceras (X-Next-After) —"
curl -sS -I "$BASE/api/notes?limit=5" | tr -d '\r' | sed -n '/^X-Next-After:/Ip' || true

echo "— Página 2 (si hay cursor) —"
NEXT=$(curl -sS -I "$BASE/api/notes?limit=5" | tr -d '\r' | awk -F': ' 'tolower($1)=="x-next-after"{print $2}' || true)
if [ -n "${NEXT:-}" ]; then
  echo "after_id=$NEXT"
  curl -sS "$BASE/api/notes?limit=5&after_id=$NEXT" | python -m json.tool | sed -n '1,30p'
else
  echo "No hay X-Next-After (1 sola página)."
fi

echo "OK ✅"
