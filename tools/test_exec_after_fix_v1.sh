#!/bin/bash
set -euo pipefail

BASE="${1:-}"
[ -z "$BASE" ] && { echo "Uso: $0 https://tu-app.onrender.com"; exit 1; }

PASS=0; FAIL=0
_tmpdir="$(mktemp -d)"; trap 'rm -rf "$_tmpdir"' EXIT

hfile() { echo "$_tmpdir/h$1.txt"; }
bfile() { echo "$_tmpdir/b$1.txt"; }

_status() { # 1=header_file
  awk 'BEGIN{s=0} /^HTTP\//{s=$2} END{print s}' "$1"
}
_hdr() { # $1=headers $2=header-name (case-insens)
  awk -v k="$2" 'BEGIN{IGNORECASE=1}
    tolower($0)~"^"tolower(k)":"{sub(/^[^:]+:[[:space:]]*/,"");print}' "$1" | head -1
}

ok()  { echo "OK  - $*";   PASS=$((PASS+1)); }
bad() { echo "FAIL- $*";   FAIL=$((FAIL+1)); }

# 1) /api/health (JSON {"ok":true})
curl -sS -D "$(hfile 1)" -o "$(bfile 1)" "$BASE/api/health"
s=$(_status "$(hfile 1)")
ct=$(_hdr "$(hfile 1)" "Content-Type")
if [ "$s" = "200" ] && echo "$(bfile 1)" | xargs cat | grep -q '"ok"[[:space:]]*:[[:space:]]*true'; then
  ok "health body JSON"
else
  bad "health body JSON (status=$s ct=$ct)"
fi

# 2) OPTIONS /api/notes (CORS 204 + headers)
curl -sS -D "$(hfile 2)" -o /dev/null -X OPTIONS "$BASE/api/notes"
s=$(_status "$(hfile 2)")
[ "$s" = "204" ] && ok "OPTIONS 204" || bad "OPTIONS 204"
for H in Access-Control-Allow-Origin Access-Control-Allow-Methods Access-Control-Allow-Headers Access-Control-Max-Age; do
  if _hdr "$(hfile 2)" "$H" >/dev/null; then ok "$H"; else bad "$H"; fi
done

# 3) GET /api/notes?limit=3 (CT json + Link rel=next)
curl -sS -D "$(hfile 3)" -o "$(bfile 3)" "$BASE/api/notes?limit=3"
s=$(_status "$(hfile 3)")
ct=$(_hdr "$(hfile 3)" "Content-Type")
if [ "$s" = "200" ] && echo "$ct" | grep -qi 'application/json'; then ok "GET /api/notes 200 + CT json"; else bad "GET /api/notes"; fi
if _hdr "$(hfile 3)" "Link" | grep -qi 'rel= *"?next"?'; then ok "Link: next"; else bad "Link: next"; fi

# 4) POST JSON
curl -sS -D "$(hfile 4)" -o "$(bfile 4)" -H 'Content-Type: application/json' \
  -d '{"text":"test suite ascii 1234567890"}' "$BASE/api/notes"
s=$(_status "$(hfile 4)")
if [ "$s" = "200" ] && grep -q '"id":' "$(bfile 4)"; then
  ok "publish JSON"
else
  bad "publish JSON (status=$s)"
fi

# 5) POST FORM (aceptado como JSON)
curl -sS -D "$(hfile 5)" -o "$(bfile 5)" -d "text=form shim create" "$BASE/api/notes"
s=$(_status "$(hfile 5)")
if [ "$s" = "200" ] && grep -q '"id":' "$(bfile 5)"; then
  ok "publish FORM"
else
  bad "publish FORM (status=$s)"
fi

# 6) Negativos: like/view/report 404 en id inexistente
BIGID=999999999
for path in like view report; do
  curl -sS -D "$(hfile 6)" -o /dev/null -X POST "$BASE/api/notes/$BIGID/$path" || true
  s=$(_status "$(hfile 6)")
  if [ "$s" = "404" ]; then ok "$path 404"; else bad "$path $s (esperado 404)"; fi
done

echo
echo "RESUMEN: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
