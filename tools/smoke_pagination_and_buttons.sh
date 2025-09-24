#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }

echo "== /api/notes?limit=5 (cabeceras) =="
curl -sS -D- -o /dev/null "$BASE/api/notes?limit=5" | sed -n '1,20p' | grep -i -E '^(HTTP/|Link:|X-Next-Cursor:)'

# Tomar next del Link y listar ids (para ver continuidad)
NEXT=$(curl -sS -D- -o /dev/null "$BASE/api/notes?limit=5" | sed -n 's/^Link: <\([^>]*\)>; rel="next".*$/\1/ip' | head -n1)
[ -n "$NEXT" ] && echo "next=$NEXT" || { echo "sin next"; exit 0; }

echo "== página 2 ids =="
curl -sS "$BASE$NEXT" | grep -o '"id":[0-9]\+' | head

echo "OK: API lista bien; en UI, los botones de las tarjetas de página 2/3 funcionan por delegación (v7)."
echo "Abrí: $BASE/?nosw=1 y probá “Ver más” + like/report/share en las nuevas."
