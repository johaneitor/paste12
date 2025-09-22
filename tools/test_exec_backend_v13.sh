#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"
[ -z "$BASE" ] && { echo "Uso: $0 https://host"; exit 1; }

pass=0; fail=0
ok(){ echo "OK  - $*"; pass=$((pass+1)); }
ko(){ echo "FAIL- $*"; fail=$((fail+1)); }

# Health
H="$(curl -fsS "$BASE/api/health" || true)"
echo "$H" | grep -q '"ok":true' && ok "health body JSON" || ko "health body JSON ($H)"

# CORS preflight
HDR="$(curl -fsS -i -X OPTIONS "$BASE/api/notes" | sed -n '1,40p')"
echo "$HDR" | head -n1 | grep -q "204 No Content" && ok "OPTIONS 204" || ko "OPTIONS 204"
echo "$HDR" | grep -qi '^Access-Control-Allow-Origin: \*' && ok "Access-Control-Allow-Origin" || ko "Access-Control-Allow-Origin"
echo "$HDR" | grep -qi '^Access-Control-Allow-Methods:' && ok "Access-Control-Allow-Methods" || ko "Access-Control-Allow-Methods"
echo "$HDR" | grep -qi '^Access-Control-Allow-Headers:' && ok "Access-Control-Allow-Headers" || ko "Access-Control-Allow-Headers"
echo "$HDR" | grep -qi '^Access-Control-Max-Age:' && ok "Access-Control-Max-Age" || ko "Access-Control-Max-Age"

# GET notes (+ Link)
R="$(curl -fsS -i "$BASE/api/notes?limit=3")"
echo "$R" | head -n1 | grep -q "200" && ok "GET /api/notes 200" || ko "GET /api/notes 200"
echo "$R" | grep -qi '^Content-Type: application/json' && ok "CT json" || ko "CT json"
echo "$R" | grep -qi '^Link: ' && ok "Link: next" || ko "Link: next"

# Publish JSON
PJ_STATUS="$(curl -s -o /tmp/pj.$$ -w '%{http_code}' -H 'Content-Type: application/json' -d '{"text":"test suite ascii 123456"}' "$BASE/api/notes")"
if [ "$PJ_STATUS" = "200" ] || [ "$PJ_STATUS" = "201" ]; then
  ok "publish JSON (status=$PJ_STATUS)"
else
  ko "publish JSON (status=$PJ_STATUS)"
fi

# Publish FORM
PF_STATUS="$(curl -s -o /tmp/pf.$$ -w '%{http_code}' -d "text=form ascii 123" "$BASE/api/notes")"
if [ "$PF_STATUS" = "200" ] || [ "$PF_STATUS" = "201" ]; then
  ok "publish FORM (status=$PF_STATUS)"
else
  ko "publish FORM (status=$PF_STATUS)"
fi

# Negativos 404
for a in like view report; do
  code="$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/api/notes/999999/$a")"
  [ "$code" = "404" ] && ok "$a 404" || ko "$a $code (esperado 404)"
done

echo
echo "RESUMEN: PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] || exit 1
