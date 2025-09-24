#!/usr/bin/env bash
set -Eeuo pipefail

BASE="http://127.0.0.1:8000"
LOG="${TMPDIR:-/data/data/com.termux/files/usr/tmp}/paste12_server.log"
mkdir -p "$(dirname "$LOG")"

echo "➤ Esperando health 200…"
for i in {1..30}; do
  code="$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/api/health" || true)"
  if [ "$code" = "200" ]; then echo "OK health=200"; break; fi
  sleep 1
  [ "$i" = "30" ] && { echo "Health nunca llegó a 200 (último=$code)"; exit 1; }
done

echo "➤ Forzando 3 notas nuevas (para paginación)"
for i in 1 2 3; do
  curl -sS -H 'Content-Type: application/json' -d '{"text":"check json","hours":24}' "$BASE/api/notes" >/dev/null || true
done

echo "➤ GET /api/notes?limit=2 (dump headers + body)"
OUT="$(mktemp)"; HDR="$(mktemp)"
curl -sS -i "$BASE/api/notes?limit=2" | tee "$OUT" >/dev/null
awk 'BEGIN{RS="\r?\n\r?\n"} NR==1{print > "'"$HDR"'"}' "$OUT" >/dev/null 2>&1 || true

echo
echo "— STATUS & HEADERS —"
sed -n '1,200p' "$HDR"

echo
echo "— BODY (primeras 20 líneas) —"
sed -n '1,20p' "$OUT" | sed '1,/^\s*$/d'  # quita headers, muestra body

ctype="$(awk -F': ' 'tolower($1)=="content-type"{print tolower($2)}' "$HDR" | tr -d '\r')"
echo
echo "➤ Intentando parsear JSON (si content-type es application/json)"
if echo "$ctype" | grep -q 'application/json'; then
  sed '1,/^\s*$/d' "$OUT" | python - <<'PY'
import sys, json
try:
    data = json.load(sys.stdin)
    print("OK JSON · len =", len(data))
except Exception as e:
    print("JSON parse error:", e)
PY
else
  echo "Content-Type no es JSON: $ctype"
fi

echo
echo "➤ Log (si hubiera 500, debería verse la traza):"
tail -n 120 "$LOG" || true
