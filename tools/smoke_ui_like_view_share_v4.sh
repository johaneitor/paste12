#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }

echo "== health =="; curl -sS "$BASE/api/health" && echo

# Publicar con fallback (FORM) – JSON puede devolver 400 en tu backend
TXT='UI v7 smoke —— 1234567890 abcdefghij texto largo'
ID=$(curl -fsS -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode "text=$TXT" "$BASE/api/notes" | sed -n 's/.*"id":[ ]*\([0-9]\+\).*/\1/p')
echo "id=$ID"

echo "== like ==";  curl -sS -X POST "$BASE/api/notes/$ID/like" && echo
echo "== view ==";  curl -sS -X POST "$BASE/api/notes/$ID/view" && echo

# Nota única: el flag se agrega por JS (meta name="p12-single"), por eso pedimos el HTML y grepeamos la meta
# OJO: algunos CDNs incrustan el head minimizado; el patrón es robusto.
echo "== single (HTML flags por meta) =="
HTML=$(curl -fsS "$BASE/?id=$ID&_=$(date +%s)")
echo "$HTML" | grep -qi '<meta[^>]*name=["'\'']p12-single["'\''][^>]*content=["'\'']1["'\'']' \
  && echo "OK: p12-single=1" || echo "⚠ meta p12-single no detectada (abre en navegador con ?nosw=1 para validar visualmente)"

echo "share-url: $BASE/?id=$ID"
