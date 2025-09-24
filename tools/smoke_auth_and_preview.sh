#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"

u="user$RANDOM"
p="Passw0rd!$RANDOM"
a1="7"; a2="firulais"; a3="SanMartin123"

ok(){ echo "✓ $*"; }
bad(){ echo "✗ $*"; exit 1; }

echo "== register =="
code=$(jq -n --arg u "$u" --arg p "$p" --arg a1 "$a1" --arg a2 "$a2" --arg a3 "$a3" \
  '{username:$u,password:$p,a1:$a1,a2:$a2,a3:$a3}' \
  | curl -sS -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' --data-binary @- "$BASE/api/register")
[ "$code" = "201" ] && ok "register 201" || bad "register $code"

echo "== login =="
cookies=$(mktemp)
jq -n --arg u "$u" --arg p "$p" '{username:$u,password:$p}' \
 | curl -sS -D >(grep -i '^set-cookie:' >"$cookies") -o /dev/null \
   -H 'Content-Type: application/json' --data-binary @- "$BASE/api/login"
grep -q 'sess=' "$cookies" && ok "login OK (cookie)" || bad "sin cookie sess"

echo "== create note (JSON) =="
nid=$(jq -n --arg t "nota muy larga para preview, con más de cuarenta caracteres exactos $(date -u +%H:%M:%S)" '{text:$t}' \
  | curl -sS -b "$cookies" -H 'Content-Type: application/json' --data-binary @- "$BASE/api/notes" \
  | jq -r '.item.id')
[ -n "$nid" ] && ok "nota id=$nid" || bad "no id"

echo "== /api/me & /api/my/notes =="
curl -sS -b "$cookies" "$BASE/api/me" | jq -e '.ok==true and .user.id>0' >/dev/null && ok "me OK" || bad "me"
curl -sS -b "$cookies" "$BASE/api/my/notes?limit=5" | jq -e '.ok==true and (.items|length)>=1' >/dev/null && ok "my/notes OK" || bad "my/notes"

echo "== HTML preview 'Ver más' presente =="
html=$(curl -fsS "$BASE/")
echo "$html" | grep -qi 'Ver más' && ok "preview visible" || echo "(aviso) no hallé 'Ver más' (puede tardar según bridge)"
rm -f "$cookies"
