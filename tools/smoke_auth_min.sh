#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"

pass=0; fail=0
ok(){ echo "✓ $*"; pass=$((pass+1)); }
bad(){ echo "✗ $*"; fail=$((fail+1)); }

uid="$(date +%s)"
user="u${uid}"
passw="Pass${uid}!!"
q1="7"
q2="firulais"
q3="escuela42"

echo "== register =="
code=$(curl -sS -o /tmp/r -w '%{http_code}' -H 'Content-Type: application/json' \
  --data-binary @- "$BASE/api/auth/register" <<EOF
{"username":"$user","password":"$passw","q1":"$q1","q2":"$q2","q3":"$q3"}
EOF
)
if [ "$code" = "201" ] || [ "$code" = "409" ]; then ok "register $code"; else bad "register $code"; fi

echo "== login =="
hdrs=$(mktemp)
code=$(curl -sS -D "$hdrs" -o /tmp/l -w '%{http_code}' -H 'Content-Type: application/json' \
  --data-binary @- "$BASE/api/auth/login" <<EOF
{"username":"$user","password":"$passw"}
EOF
)
[ "$code" = "200" ] && ok "login 200" || bad "login $code"
cookie="$(awk 'BEGIN{IGNORECASE=1}/^Set-Cookie:/{print $0}' "$hdrs" | sed -n 's/^Set-Cookie:\s*//Ip' | head -n1)"
rm -f "$hdrs"

echo "== me (cookie) =="
code=$(curl -sS -o /tmp/m -w '%{http_code}' -H "Cookie: $cookie" "$BASE/api/auth/me")
[ "$code" = "200" ] && ok "me 200" || bad "me $code"

echo "== logout =="
code=$(curl -sS -o /tmp/o -w '%{http_code}' -H "Cookie: $cookie" -X POST "$BASE/api/auth/logout")
[ "$code" = "200" ] && ok "logout 200" || bad "logout $code"

echo "== me (sin cookie) =="
code=$(curl -sS -o /tmp/m2 -w '%{http_code}' "$BASE/api/auth/me")
[ "$code" = "401" ] && ok "me 401 tras logout" || bad "me $code tras logout"

echo "RESUMEN: ok=$pass, fail=$fail"
[ $fail -eq 0 ] || exit 1
