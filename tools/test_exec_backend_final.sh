#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"

pass(){ printf "OK  - %s\n" "$*"; }
fail(){ printf "FAIL- %s\n" "$*" ; exit 1; }

# 1) Health
J="$(curl -fsS "$BASE/api/health")" || fail "health"
echo "$J" | python - <<'PY' || exit 1
import sys, json
j=json.loads(sys.stdin.read()); assert j.get("ok") is True
PY
pass "health body JSON"

# 2) CORS preflight
H="$(curl -fsS -i -X OPTIONS "$BASE/api/notes")"
grep -q '^HTTP/.* 204' <<<"$H"        || fail "OPTIONS 204"
grep -qi '^access-control-allow-origin: \*' <<<"$H" || fail "ACAO"
grep -qi '^access-control-allow-methods: .*GET.*POST.*' <<<"$H" || fail "ACAM"
grep -qi '^access-control-allow-headers: .*Content-Type' <<<"$H" || fail "ACAH"
grep -qi '^access-control-max-age:' <<<"$H" || fail "Max-Age"
pass "CORS OK"

# 3) GET + Link
R="$(curl -fsS -i "$BASE/api/notes?limit=10")"
grep -qi '^content-type: application/json' <<<"$R" || fail "CT json"
grep -qi '^link: .*rel="next"' <<<"$R" || fail "Link: next"
pass "GET /api/notes + Link"

# 4) POST JSON
J="$(curl -fsS -H 'Content-Type: application/json' \
  -d '{"text":"test suite ascii 123456"}' "$BASE/api/notes" )" || fail "publish JSON HTTP"
echo "$J" | python - <<'PY' || exit 1
import sys, json
j=json.loads(sys.stdin.read())
assert ('id' in j) or (j.get('ok') is True) or (j.get('item') and j['item'].get('id'))
PY
pass "publish JSON"

# 5) POST FORM (fallback)
J="$(curl -fsS -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'text=form suite ascii 123456' "$BASE/api/notes")" || fail "publish FORM HTTP"
echo "$J" | python - <<'PY' || exit 1
import sys, json
j=json.loads(sys.stdin.read())
assert ('id' in j) or (j.get('ok') is True) or (j.get('item') and j['item'].get('id'))
PY
pass "publish FORM"

# 6) Negativos
for p in like view report; do
  code="$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/api/notes/999999/$p")"
  [ "$code" = "404" ] || fail "$p 404"
done
pass "negativos 404"

echo "✔ Todo OK (final)."
