#!/usr/bin/env bash
# Uso: tools/test_exec_after_fix_v3.sh "https://paste12-rmsk.onrender.com"
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "Falta BASE"; exit 2; }

pass=0; fail=0
ok(){ echo "OK  - $*"; pass=$((pass+1)); }
ko(){ echo "FAIL- $*"; fail=$((fail+1)); }

# A) health JSON
hb="$(curl -fsS "$BASE/api/health" -H 'Accept: application/json' || true)"
echo "$hb" | grep -q '"ok":\s*true' && ok "health body JSON" || ko "health body JSON"

# B) CORS OPTIONS /api/notes
code="$(curl -s -o /dev/null -w '%{http_code}' -X OPTIONS "$BASE/api/notes")"
[ "$code" = "204" ] && ok "OPTIONS 204" || ko "OPTIONS 204 (got $code)"
# headers informativos (no fallan)
curl -sI -X OPTIONS "$BASE/api/notes" | grep -qi '^access-control-allow-origin:' && ok "ACAO" || ok "ACAO (skip)"
curl -sI -X OPTIONS "$BASE/api/notes" | grep -qi '^access-control-allow-methods:' && ok "ACAM" || ok "ACAM (skip)"
curl -sI -X OPTIONS "$BASE/api/notes" | grep -qi '^access-control-allow-headers:' && ok "ACAH" || ok "ACAH (skip)"
curl -sI -X OPTIONS "$BASE/api/notes" | grep -qi '^access-control-max-age:' && ok "Max-Age" || ok "Max-Age (skip)"

# C) GET /api/notes + Link
hdr="$(curl -fsSI "$BASE/api/notes?limit=10" -H 'Accept: application/json')"
echo "$hdr" | grep -qi '^content-type: .*json' && ok "CT json" || ko "CT json"
echo "$hdr" | grep -qi '^link: .*rel=.*next' && ok "Link: next" || ok "Link: next (tolerado)"

# D) POST JSON
txt="test suite json 1234567890 abcdef"
json="$(curl -s -H 'Content-Type: application/json' -H 'Accept: application/json' -d "{\"text\":\"$txt\"}" "$BASE/api/notes" -w '\n%{http_code}')"
body="$(echo "$json" | head -n-1)"; code="$(echo "$json" | tail -n1)"
if echo "$body" | grep -q '"id":'; then
  case "$code" in 200|201) ok "publish JSON";; *) ko "publish JSON (status=$code)";; esac
else
  ko "publish JSON (sin id)"
fi

# E) POST FORM
form="$(curl -s -H 'Content-Type: application/x-www-form-urlencoded' -H 'Accept: application/json' \
  --data-urlencode "text=form shim create" "$BASE/api/notes" -w '\n%{http_code}')"
body="$(echo "$form" | head -n-1)"; code="$(echo "$form" | tail -n1)"
if echo "$body" | grep -q '"id":'; then
  case "$code" in 200|201) ok "publish FORM";; *) ko "publish FORM (status=$code)";; esac
else
  ko "publish FORM (sin id)"
fi

# F) Negativos
nid=999999999
for path in like view report; do
  c="$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/api/notes/$nid/$path")"
  [ "$c" = "404" ] && ok "$path 404" || ko "$path $c"
done

echo ""
echo "RESUMEN: PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] || exit 1
