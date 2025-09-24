#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"
U="user$(date -u +%H%M%S)"
P="Passw0rd!$(date +%s)"
A1="7"
A2="firulais"
A3="mi-primaria"

ok(){ echo "✓ $*"; }
bad(){ echo "✗ $*"; exit 1; }

echo "== register =="
code=$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$BASE/api/auth/register" \
  -H 'Content-Type: application/json' --data-binary @- <<EOF
{"username":"$U","password":"$P","a1":"$A1","a2":"$A2","a3":"$A3"}
EOF
)
[ "$code" = "201" ] || bad "register $code"

echo "== login =="
LOGIN=$(curl -fsS -X POST "$BASE/api/auth/login" -H 'Content-Type: application/json' \
  --data-binary @- <<EOF
{"username":"$U","password":"$P"}
EOF
)
tok=$(echo "$LOGIN" | jq -r '.token')
[ -n "$tok" ] || bad "sin token"
ok "token emitido"

echo "== me =="
curl -fsS -H "Authorization: Bearer $tok" "$BASE/api/auth/me" | jq -e '.ok==true and .user.username!=""' >/dev/null
ok "me OK"

echo "== crear nota (JSON) =="
NID=$(jq -n --arg t "nota muy larga para probar ver más — $(date -u +%H:%M:%S) — xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" \
      '{text:$t}' \
  | curl -fsS -H 'Content-Type: application/json' --data-binary @- "$BASE/api/notes" \
  | jq -r '.item.id')
[ -n "$NID" ] || bad "no se creó nota"

echo "== UI: Ver más presente =="
HTML=$(curl -fsS "$BASE/")
echo "$HTML" | grep -qi 'Ver más' && ok "botón/verbo 'Ver más' detectado" || bad "no encuentro 'Ver más'"

echo "== logout =="
curl -fsS -X POST -H "Authorization: Bearer $tok" "$BASE/api/auth/logout" >/dev/null
code=$(curl -sS -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $tok" "$BASE/api/auth/me" || true)
[ "$code" = "403" ] && ok "logout invalidó token" || bad "logout no invalidó token (code=$code)"

echo "DONE"
