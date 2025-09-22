#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"
[ -n "$BASE" ] || { echo "Uso: $0 https://tu-app.onrender.com" >&2; exit 1; }

pass(){ printf "OK  - %s\n" "$*"; }
fail(){ printf "FAIL- %s\n" "$*"; }

# A) health JSON
body="$(curl -fsS "$BASE/api/health" || true)"
python - <<PY > /dev/null 2>&1 || { fail "health body: $body"; goto_b=1; }
import json,sys
j=json.loads("""$body""")
assert j.get("ok") is True
PY
[ "${goto_b:-0}" -eq 1 ] || pass "health body JSON"

# B) CORS preflight
hdr="$(curl -fsSI -X OPTIONS "$BASE/api/notes" || true)"
echo "$hdr" | grep -qiE '^HTTP/.* 204'     && pass "OPTIONS 204" || fail "OPTIONS 204"
echo "$hdr" | grep -qi '^Access-Control-Allow-Origin: \*'  && pass "ACAO" || fail "ACAO"
echo "$hdr" | grep -qi 'Access-Control-Allow-Methods: .*GET,POST,OPTIONS' && pass "ACAM" || fail "ACAM"
echo "$hdr" | grep -qi 'Access-Control-Allow-Headers: .*Content-Type'     && pass "ACAH" || fail "ACAH"
echo "$hdr" | grep -qi 'Access-Control-Max-Age: 86400'                    && pass "Max-Age" || fail "Max-Age"

# C) GET /api/notes
r="$(mktemp)"; curl -fsSI "$BASE/api/notes?limit=3" > "$r" || true
grep -qiE '^HTTP/.* 200' "$r" && pass "GET /api/notes 200" || fail "GET /api/notes 200"
grep -qi 'Content-Type: application/json' "$r" && pass "CT json" || fail "CT json"
grep -qi '^Link: .*rel="next"' "$r" && pass "Link: next" || fail "Link: next"
rm -f "$r"

# D) publish JSON
jid="$(curl -fsS -H 'Content-Type: application/json' -d '{"text":"test-suite json —— 1234567890 abcdefghij"}' "$BASE/api/notes" \
  | python - <<'PY'
import json,sys; j=json.load(sys.stdin); print(j.get("id") or j.get("item",{}).get("id") or "")
PY
)"
if [ -n "$jid" ]; then pass "publish JSON id=$jid"; else fail "publish JSON"; fi

# E) publish FORM (shim convierte a JSON)
fid="$(curl -fsS -H 'Accept: application/json' -d 'text=test-suite form —— 1234567890 abcdefghij' "$BASE/api/notes" \
  | python - <<'PY'
import json,sys; j=json.load(sys.stdin); print(j.get("id") or j.get("item",{}).get("id") or "")
PY
)"
if [ -n "$fid" ]; then pass "publish FORM id=$fid"; else fail "publish FORM"; fi

echo
echo "RESUMEN listo."
