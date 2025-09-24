#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }
echo "== Salud =="
curl -fsS "$BASE/api/health" && echo

echo "== Crear (JSON) =="
DATA="$(printf '{"text":"ui smoke %s 1234567890 abcdefghij"}' "$(date -u +%H:%M:%SZ)")"
curl -fsS -i -H 'Content-Type: application/json' --data-binary "$DATA" "$BASE/api/notes" | sed -n '1,20p'
echo

echo "== Crear (FORM fallback) =="
curl -fsS -i -H 'Content-Type: application/x-www-form-urlencoded' \
  --data "text=ui+smoke+form+$(date -u +%H:%M:%SZ)+1234567890+abcdefghijkl" \
  "$BASE/api/notes" | sed -n '1,20p'
echo

echo "== Page 1 (limit=5) =="
curl -fsS -D /tmp/h1 "$BASE/api/notes?limit=5" -o /tmp/b1 >/dev/null || true
sed -n '1p;/^[Ll]ink:/p;/^X-Next-Cursor:/p' /tmp/h1
jq -r '.items[]?.id' < /tmp/b1 | sed 's/^/id: /'

NEXT="$(sed -n 's/^[Ll]ink:\s*<\([^>]*\)>;.*$/\1/p' /tmp/h1 | head -n1)"
if [ -n "$NEXT" ]; then
  echo "== Page 2 =="
  curl -fsS -D /tmp/h2 "$BASE$NEXT" -o /tmp/b2 >/dev/null || true
  sed -n '1p;/^[Ll]ink:/p;/^X-Next-Cursor:/p' /tmp/h2
  jq -r '.items[]?.id' < /tmp/b2 | sed 's/^/id: /'
else
  echo "⚠ sin Link rel=next en Page 1"
fi

echo "== Verificar encabezados CORS en POST (con Origin) =="
curl -fsS -i -H 'Origin: https://example.com' -H 'Content-Type: application/json' \
  --data-binary "$DATA" "$BASE/api/notes" | sed -n '1,20p' || true

echo "Listo."
