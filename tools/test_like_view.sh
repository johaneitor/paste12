#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"
if [ -z "$BASE" ]; then
  echo "Uso: $0 https://tu-app.onrender.com" >&2
  exit 1
fi

resp="$(curl -fsS -H 'Content-Type: application/json' -d '{"text":"like/view/report test"}' "$BASE/api/notes")"
id="$(printf "%s" "$resp" | sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p' | head -n1)"
if [ -z "$id" ]; then
  echo "No pude obtener id de la nota" >&2
  echo "$resp"
  exit 1
fi
echo "BASE=$BASE"
echo "note id=$id"

curl -fsS -X POST "$BASE/api/notes/$id/like" || { echo "like falló"; exit 1; }
curl -fsS -X POST "$BASE/api/notes/$id/view" || { echo "view falló (si 404, backend no implementa 'view')"; exit 0; }
curl -fsS -X POST "$BASE/api/notes/$id/report" || true
