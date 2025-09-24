#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"
[ -n "$BASE" ] || { echo "Uso: $0 https://tu-app.onrender.com"; exit 1; }

red(){ printf "\e[31m%s\e[0m\n" "$*"; }
grn(){ printf "\e[32m%s\e[0m\n" "$*"; }
ylw(){ printf "\e[33m%s\e[0m\n" "$*"; }

fail=0

# 1) health JSON
body="$(curl -fsS "$BASE/api/health" || true)"
if [ "$body" = '{"ok":true}' ]; then grn "OK  - health body JSON"; else red "FAIL- health body: $body"; fail=$((fail+1)); fi

# 2) CORS OPTIONS /api/notes → 204 + headers
hdrs="$(curl -isS -X OPTIONS "$BASE/api/notes")"
status="$(printf "%s" "$hdrs" | sed -n '1p')"
if printf "%s" "$status" | grep -q "204"; then grn "OK  - OPTIONS 204"; else red "FAIL- OPTIONS 204"; fail=$((fail+1)); fi
for k in "Access-Control-Allow-Origin: *" \
         "Access-Control-Allow-Methods: GET,POST,OPTIONS" \
         "Access-Control-Allow-Headers: Content-Type" \
         "Access-Control-Max-Age: 86400"
do
  if printf "%s" "$hdrs" | grep -qiF "$k"; then grn "OK  - $(printf "%s" "$k" | cut -d: -f1)"; else red "FAIL- $(printf "%s" "$k" | cut -d: -f1)"; fail=$((fail+1)); fi
done

# 3) GET /api/notes?limit=3 => 200 JSON + Link
gout="$(curl -isS "$BASE/api/notes?limit=3")"
if echo "$gout" | sed -n '1p' | grep -q "200"; then grn "OK  - GET /api/notes 200"; else red "FAIL- GET /api/notes"; fail=$((fail+1)); fi
if echo "$gout" | grep -qi "^content-type: application/json"; then grn "OK  - CT json"; else red "FAIL- CT json"; fail=$((fail+1)); fi
if echo "$gout" | grep -qi '^link: .*rel="next"'; then grn "OK  - Link: next"; else red "FAIL- Link: next"; fail=$((fail+1)); fi

# 4) POST JSON -> debe crear
json_out="$(curl -fsS -H 'Content-Type: application/json' -d '{"text":"test-suite json —— 1234567890 abcdefghij"}' "$BASE/api/notes" || true)"
jid="$(python - <<'PY'
import json,sys
try:
    obj=json.loads(sys.stdin.read() or "{}")
    print(obj.get("id",""))
except Exception:
    print("")
PY
<<<"$json_out")"
if [ -n "$jid" ]; then grn "OK  - publish JSON id=$jid"; else red "FAIL- publish JSON ($json_out)"; fail=$((fail+1)); fi

# 5) POST form -> debe crear (FORM→JSON)
form_out="$(curl -fsS -d "text=form shim create" "$BASE/api/notes" || true)"
fid="$(python - <<'PY'
import json,sys
try:
    obj=json.loads(sys.stdin.read() or "{}")
    print(obj.get("id",""))
except Exception:
    print("")
PY
<<<"$form_out")"
if [ -n "$fid" ]; then grn "OK  - publish FORM id=$fid"; else red "FAIL- publish FORM ($form_out)"; fail=$((fail+1)); fi

# 6) Negativos básicos (404 en inexistentes)
for a in like view report; do
  code="$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE/api/notes/999999/$a")"
  if [ "$code" = "404" ]; then grn "OK  - $a 404"; else ylw "WARN- $a esperado 404; got $code"; fi
done

echo
if [ "$fail" -eq 0 ]; then grn "RESUMEN: PASS ✅"; exit 0; else red "RESUMEN: $fail fallas ❌"; exit 1; fi
