#!/usr/bin/env bash
set -Eeuo pipefail

BASE="http://127.0.0.1:8000"

echo "➤ Esperando health 200…"
for i in {1..30}; do
  code="$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/api/health" || true)"
  if [ "$code" = "200" ]; then echo "OK health=200"; break; fi
  sleep 1
done

echo "➤ Forzando 3 notas para paginar"
for i in 1 2 3; do
  curl -sS -H 'Content-Type: application/json' -d '{"text":"check json v3","hours":24}' "$BASE/api/notes" >/dev/null || true
done

TMP="$(mktemp)"
curl -sS -i "$BASE/api/notes?limit=2" | tr -d '\r' > "$TMP"

echo
echo "— STATUS & HEADERS —"
sed -n '1,/^$/p' "$TMP"

echo
echo "— BODY (primeras 2000 chars) —"
# OJO: SIN -n — esto imprime el body correctamente
sed -e '1,/^$/d' "$TMP" | head -c 2000; echo

ctype="$(sed -n '1,/^$/p' "$TMP" | awk -F': ' 'tolower($1)=="content-type"{print tolower($2)}')"
echo
echo "➤ Parse JSON si content-type=application/json"
if echo "$ctype" | grep -q 'application/json'; then
  sed -e '1,/^$/d' "$TMP" | python - <<'PY'
import sys, json
try:
    data=json.load(sys.stdin); print("OK JSON · len =", len(data))
except Exception as e:
    print("JSON parse error:", e)
PY
else
  echo "Content-Type no JSON: $ctype"
fi
