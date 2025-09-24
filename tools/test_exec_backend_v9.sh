#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [[ -z "${BASE}" ]] && { echo "Uso: $0 https://tu-app"; exit 2; }

fail=0
say(){ printf '%-38s %s\n' "$1" "$2"; }

# /api/health -> {"ok":true}
h="$(curl -fsS "$BASE/api/health" || true)"
if [[ "$h" == '{"ok":true}' ]]; then say "OK  - health body JSON" " "; else say "FAIL- health body JSON" "$h"; ((fail++)); fi

# OPTIONS /api/notes -> 204 + CORS
hdr="$(curl -fsSI -X OPTIONS "$BASE/api/notes" || true)"
grep -Eq '^HTTP/[^ ]+ 204' <<<"$hdr" && say "OK  - OPTIONS 204" "" || { say "FAIL- OPTIONS 204" ""; ((fail++)); }
grep -qi '^access-control-allow-origin: \*' <<<"$hdr" && say "OK  - Access-Control-Allow-Origin" "" || { say "FAIL- Access-Control-Allow-Origin" ""; ((fail++)); }
grep -qi '^access-control-allow-methods: .*GET.*POST.*OPTIONS' <<<"$hdr" && say "OK  - Access-Control-Allow-Methods" "" || { say "FAIL- Access-Control-Allow-Methods" ""; ((fail++)); }
grep -qi '^access-control-allow-headers: .*content-type' <<<"$hdr" && say "OK  - Access-Control-Allow-Headers" "" || { say "FAIL- Access-Control-Allow-Headers" ""; ((fail++)); }
grep -qi '^access-control-max-age:' <<<"$hdr" && say "OK  - Access-Control-Max-Age" "" || { say "FAIL- Access-Control-Max-Age" ""; ((fail++)); }

# GET /api/notes?limit=3 -> 200 + CT json + Link: next
g_hdr="$(curl -fsSI "$BASE/api/notes?limit=3")"
grep -Eq '^HTTP/[^ ]+ 200' <<<"$g_hdr" && say "OK  - GET /api/notes 200" "" || { say "FAIL- GET /api/notes 200" ""; ((fail++)); }
grep -qi '^content-type: application/json' <<<"$g_hdr" && say "OK  - CT json" "" || { say "FAIL- CT json" ""; ((fail++)); }
grep -qi '^link: .*rel="next"' <<<"$g_hdr" && say "OK  - Link: next" "" || { say "FAIL- Link: next" ""; ((fail++)); }

# POST JSON
j_resp="$(curl -fsS -H 'Content-Type: application/json' -H 'Accept: application/json' -d '{"text":"test-suite json —— 1234567890 abcdefghij"}' "$BASE/api/notes" || true)"
jid="$(python - <<PY 2>/dev/null
import json,sys; 
try:
    j=json.loads(sys.stdin.read())
    print(j.get("id") or "")
except: 
    print("")
PY
<<<"$j_resp")"
if [[ -n "$jid" ]]; then say "OK  - publish JSON id=$jid" ""; else say "FAIL- publish JSON ($j_resp)" ""; ((fail++)); fi

# POST FORM
f_resp="$(curl -fsS -H 'Content-Type: application/x-www-form-urlencoded' -H 'Accept: application/json' --data-urlencode "text=form shim create" "$BASE/api/notes" || true)"
fid="$(python - <<PY 2>/dev/null
import json,sys; 
try:
    j=json.loads(sys.stdin.read())
    print(j.get("id") or "")
except: 
    print("")
PY
<<<"$f_resp")"
if [[ -n "$fid" ]]; then say "OK  - publish FORM id=$fid" ""; else say "FAIL- publish FORM ($f_resp)" ""; ((fail++)); fi

# Negativos 404
for a in like view report; do
  c=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE/api/notes/999999/$a")
  if [[ "$c" == "404" ]]; then say "OK  - $a 404" ""; else say "FAIL- $a $c" ""; ((fail++)); fi
done

echo
[[ $fail -eq 0 ]] && echo "RESUMEN: ✅ todo OK" || echo "RESUMEN: ❌ fallas=$fail"
exit $fail
