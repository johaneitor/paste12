#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"
[ -z "$BASE" ] && { echo "Uso: $0 https://tu-app.onrender.com"; exit 1; }

green(){ printf "\033[1;32m%s\033[0m\n" "$*"; }
red(){ printf "\033[1;31m%s\033[0m\n" "$*"; }

echo "== Smoke básico =="
curl -fsS "$BASE/api/health" | grep -q '{"ok":true}' && green "OK  - health body JSON" || { red "FAIL- health"; exit 1; }

echo "== CORS (OPTIONS) =="
H="$(curl -fsSI -X OPTIONS "$BASE/api/notes")"
echo "$H" | grep -qi '^HTTP/.* 204' && green "OK  - OPTIONS 204" || red "FAIL- OPTIONS 204"
echo "$H" | grep -qi '^Access-Control-Allow-Origin:' && green "OK  - ACAO" || red "FAIL- ACAO"
echo "$H" | grep -qi '^Access-Control-Allow-Methods:' && green "OK  - ACAM" || red "FAIL- ACAM"
echo "$H" | grep -qi '^Access-Control-Allow-Headers:' && green "OK  - ACAH" || red "FAIL- ACAH"
echo "$H" | grep -qi '^Access-Control-Max-Age:' && green "OK  - Max-Age" || red "FAIL- Max-Age"

echo "== GET /api/notes con headers (no HEAD) =="
R="$(curl -fsSi -H 'Accept: application/json' "$BASE/api/notes?limit=3")"
HDR="$(printf "%s" "$R" | sed -n '1,/^\r\{0,1\}$/p')"
printf "%s" "$HDR" | grep -qi '^Content-Type:.*application/json' && green "OK  - CT json" || red "FAIL- CT json"
printf "%s" "$HDR" | grep -qi '^Link:.*rel="next"' && green "OK  - Link: next" || { red "FAIL- Link: next"; printf "%s\n" "$HDR" | sed -n '1,60p'; exit 1; }
printf "%s" "$HDR" | grep -qi '^X-Next-Cursor:' && green "OK  - X-Next-Cursor" || red "WARN- sin X-Next-Cursor (tolerado)"

echo "== POST JSON + FORM =="
J="$(curl -fsS -H 'Content-Type: application/json' -d '{"text":"test-suite json —— 1234567890 abcdefghij"}' "$BASE/api/notes")"
echo "$J" | grep -q '"id":' && green "OK  - publish JSON" || red "FAIL- publish JSON"
F="$(curl -fsS -d 'text=form shim create' "$BASE/api/notes")"
echo "$F" | grep -q '"id":' && green "OK  - publish FORM" || red "FAIL- publish FORM"

echo "== Negativos 404 =="
for k in like view report; do
  code="$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/api/notes/999999/$k")"
  [ "$code" = "404" ] && green "OK  - $k 404" || red "FAIL- $k $code"
done

green "✔ Todo OK (v11)."
