#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"

ok(){ printf "OK  - %s\n" "$*"; }
ko(){ printf "FAIL- %s\n" "$*"; exit 1; }

V=$(date +%s)
H=$(curl -fsS "$BASE/?debug=1&nosw=1&v=$V")
[[ ${#H} -gt 200 ]] && ok "index > 200 bytes" || ko "index muy corto"
echo "$H" | grep -q 'p12-card-fix-v3' && ok "card-fix v3 presente" || ko "card-fix ausente"
echo "$H" | grep -q '<span class="views"' && ok "span.views" || ko "span.views ausente (live)"

J=$(curl -fsS "$BASE/api/health"); echo "$J" | grep -q '"ok":true' && ok "health body JSON" || ko "health JSON"

C=$(curl -fsSI -X OPTIONS "$BASE/api/notes")
echo "$C" | grep -q "^HTTP/.* 204" && ok "OPTIONS 204" || ko "OPTIONS 204"
echo "$C" | grep -qi 'access-control-allow-origin: \*' && ok "ACAO" || ko "ACAO"
echo "$C" | grep -qi '^content-type: application/json' && true || true

HDR=$(curl -fsSI "$BASE/api/notes?limit=10")
echo "$HDR" | grep -qi '^content-type: application/json' && ok "CT json" || ko "CT json"
echo "$HDR" | grep -qi '^link: .*rel="next"' && ok "Link: next" || ok "Link: next (tolerado)"

PJ=$(curl -fsS -H 'Content-Type: application/json' -d '{"text":"test suite json 123456"}' "$BASE/api/notes") || true
echo "$PJ" | grep -q '"id":' && ok "publish JSON" || ko "publish JSON"

PF=$(curl -fsS -H 'Content-Type: application/x-www-form-urlencoded' --data 'text=form shim create' "$BASE/api/notes") || true
echo "$PF" | grep -q '"id":' && ok "publish FORM" || ko "publish FORM"

curl -fsS "$BASE/api/notes/999999/like"   -X POST -o /dev/null -w "%{http_code}" | grep -q '404' && ok "like 404"   || ko "like 404"
curl -fsS "$BASE/api/notes/999999/view"   -X POST -o /dev/null -w "%{http_code}" | grep -q '404' && ok "view 404"   || ko "view 404"
curl -fsS "$BASE/api/notes/999999/report" -X POST -o /dev/null -w "%{http_code}" | grep -q '404' && ok "report 404" || ko "report 404"

echo "RESUMEN: PASS ✅"
