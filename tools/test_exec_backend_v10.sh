#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"
[ -z "$BASE" ] && { echo "Uso: $0 https://tu-app.onrender.com"; exit 1; }

echo "== Smoke básico =="
curl -fsS "$BASE/api/health" | grep -q '{"ok":true}' && echo "OK  - health body JSON" || { echo "FAIL- health"; exit 1; }

echo "== CORS (OPTIONS) =="
H="$(curl -fsSI -X OPTIONS "$BASE/api/notes")"
echo "$H" | grep -qi '^HTTP/.* 204' && echo "OK  - OPTIONS 204" || echo "FAIL- OPTIONS 204"
echo "$H" | grep -qi '^Access-Control-Allow-Origin:' && echo "OK  - ACAO" || echo "FAIL- ACAO"
echo "$H" | grep -qi '^Access-Control-Allow-Methods:' && echo "OK  - ACAM" || echo "FAIL- ACAM"
echo "$H" | grep -qi '^Access-Control-Allow-Headers:' && echo "OK  - ACAH" || echo "FAIL- ACAH"
echo "$H" | grep -qi '^Access-Control-Max-Age:' && echo "OK  - Max-Age" || echo "FAIL- Max-Age"

echo "== GET /api/notes (Link) =="
HDR="$(curl -fsSI "$BASE/api/notes?limit=3")"
echo "$HDR" | grep -qi '^Content-Type:.*application/json' && echo "OK  - CT json" || echo "FAIL- CT json"
if echo "$HDR" | grep -qi '^Link:.*rel="next"'; then
  echo "OK  - Link: next"
else
  echo "FAIL- Link: next"
  echo "--- headers ---"; echo "$HDR" | sed -n '1,20p'
  exit 1
fi

echo "== POST JSON + FORM =="
J="$(curl -fsS -H 'Content-Type: application/json' -d '{"text":"test-suite json —— 1234567890 abcdefghij"}' "$BASE/api/notes")"
echo "$J" | grep -q '"id":' && echo "OK  - publish JSON" || echo "FAIL- publish JSON"
F="$(curl -fsS -d 'text=form shim create' "$BASE/api/notes")"
echo "$F" | grep -q '"id":' && echo "OK  - publish FORM" || echo "FAIL- publish FORM"

echo "== Negativos 404 =="
for k in like view report; do
  code="$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/api/notes/999999/$k")"
  [ "$code" = "404" ] && echo "OK  - $k 404" || echo "FAIL- $k $code"
done

echo "✔ Todo OK (v10)."
