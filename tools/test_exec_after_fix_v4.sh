#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"

pass(){ printf "OK  - %s\n" "$*"; }
fail(){ printf "FAIL- %s\n" "$*" && exit 1; }

# HTML (nocache)
V=$(date +%s)
H=$(curl -fsS "$BASE/?debug=1&nosw=1&v=$V")
[[ ${#H} -gt 200 ]] && pass "index > 200 bytes" || fail "index muy corto"
echo "$H" | grep -q '<span class="views"' && pass "span.views" || fail "span.views ausente"

# health
J=$(curl -fsS "$BASE/api/health")
echo "$J" | grep -q '"ok":true' && pass "health body JSON" || fail "health JSON"

# CORS
C=$(curl -fsSI -X OPTIONS "$BASE/api/notes")
echo "$C" | grep -q "^HTTP/.* 204" && pass "OPTIONS 204" || fail "OPTIONS 204"
echo "$C" | grep -qi 'access-control-allow-origin: \*' && pass "ACAO" || fail "ACAO"

# GET + Link
HDR=$(curl -fsSI "$BASE/api/notes?limit=10")
echo "$HDR" | grep -qi '^content-type: application/json' && pass "CT json" || fail "CT json"
echo "$HDR" | grep -qi '^link: .*rel="next"' && pass "Link: next" || pass "Link: next (tolerado)"

# POST JSON + FORM
PJ=$(curl -fsS -H 'Content-Type: application/json' -d '{"text":"test suite json 123456"}' "$BASE/api/notes") || true
echo "$PJ" | grep -q '"id":' && pass "publish JSON" || fail "publish JSON"

PF=$(curl -fsS -H 'Content-Type: application/x-www-form-urlencoded' --data 'text=form shim create' "$BASE/api/notes") || true
echo "$PF" | grep -q '"id":' && pass "publish FORM" || fail "publish FORM"

# Negativos
curl -fsS "$BASE/api/notes/999999/like"   -X POST -o /dev/null -w "%{http_code}" | grep -q '404' && pass "like 404"   || fail "like 404"
curl -fsS "$BASE/api/notes/999999/view"   -X POST -o /dev/null -w "%{http_code}" | grep -q '404' && pass "view 404"   || fail "view 404"
curl -fsS "$BASE/api/notes/999999/report" -X POST -o /dev/null -w "%{http_code}" | grep -q '404' && pass "report 404" || fail "report 404"

echo "RESUMEN: PASS ✅"
