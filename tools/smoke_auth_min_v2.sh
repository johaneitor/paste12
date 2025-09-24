#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"

pass=0; fail=0
ok(){ echo "✓ $*"; pass=$((pass+1)); }
bad(){ echo "✗ $*"; fail=$((fail+1)); }

needs(){ command -v "$1" >/dev/null 2>&1 || { echo "✗ falta $1"; exit 2; }; }
needs curl
needs awk
needs sed
needs jq

# --- preflight: ¿existen endpoints? ---
pre() {
  local p="$1" m="${2:-GET}"
  curl -sS -o /dev/null -w '%{http_code}' -X "$m" "$BASE$p"
}
[ "$(pre /api/health GET)" = "200" ] || { bad "health != 200"; exit 1; }
rc="$(pre /api/auth/register POST)"
if [ "$rc" = "404" ]; then
  bad "/api/auth/register no está montado (404). ¿Aplicaste y desplegaste el patch de auth?"
  echo "Sugerido: python tools/append_auth_min_from_file.py  &&  git push  &&  redeploy"
  exit 1
fi

uid="$(date +%s)"
user="u${uid}"
passw="Pass${uid}!!"
q1="7"; q2="firulais"; q3="escuela42"

# --- register ---
echo "== register =="
code=$(curl -sS -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' \
  --data-binary @- "$BASE/api/auth/register" <<EOF
{"username":"$user","password":"$passw","q1":"$q1","q2":"$q2","q3":"$q3"}
EOF
)
if [ "$code" = "201" ] || [ "$code" = "409" ]; then ok "register $code"; else bad "register $code"; fi

# --- login ---
echo "== login =="
hdrs="$(mktemp)"; body="$(mktemp)"
code=$(curl -sS -D "$hdrs" -o "$body" -w '%{http_code}' -H 'Content-Type: application/json' \
  --data-binary @- "$BASE/api/auth/login" <<EOF
{"username":"$user","password":"$passw"}
EOF
)
[ "$code" = "200" ] && ok "login 200" || { bad "login $code"; echo "Body:"; cat "$body"; rm -f "$hdrs" "$body"; exit 1; }
cookie="$(awk 'BEGIN{IGNORECASE=1}/^Set-Cookie:/{sub(/^Set-Cookie:[[:space:]]*/,"");print;exit}' "$hdrs")"
rm -f "$hdrs" "$body"

# --- me (cookie) ---
echo "== me (cookie) =="
code=$(curl -sS -o /dev/null -w '%{http_code}' -H "Cookie: $cookie" "$BASE/api/auth/me")
[ "$code" = "200" ] && ok "me 200" || bad "me $code"

# --- logout ---
echo "== logout =="
code=$(curl -sS -o /dev/null -w '%{http_code}' -H "Cookie: $cookie" -X POST "$BASE/api/auth/logout")
[ "$code" = "200" ] && ok "logout 200" || bad "logout $code"

# --- me (sin cookie) ---
echo "== me (sin cookie) =="
code=$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/api/auth/me")
[ "$code" = "401" ] && ok "me 401 tras logout" || bad "me $code tras logout"

echo "RESUMEN: ok=$pass, fail=$fail"
[ $fail -eq 0 ] || exit 1
