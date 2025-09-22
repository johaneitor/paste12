#!/usr/bin/env bash
set -euo pipefail

BASE="${1:-${BASE:-}}"
[[ -z "${BASE}" ]] && { echo "Uso: $0 https://tu-app.onrender.com"; exit 2; }

pass=0; fail=0
ok(){ printf "OK  - %s\n" "$1"; ((pass++)) || true; }
ko(){ printf "FAIL- %s\n" "$1"; ((fail++)) || true; }

tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' EXIT

# --- /api/health (JSON {"ok":true})
hb="$(curl -fsS "$BASE/api/health" || true)"
if printf "%s" "$hb" | grep -q '"ok"[[:space:]]*:[[:space:]]*true'; then
  ok "health body JSON"
else
  ko "health body (quería JSON con ok=true)"
fi

# --- OPTIONS /api/notes (CORS 204)
h="$tmpdir/opts.h"
curl -fsS -o /dev/null -D "$h" -X OPTIONS "$BASE/api/notes" || true
grep -iq '^HTTP/.* 204' "$h" && ok "OPTIONS 204" || ko "OPTIONS 204"
grep -iq '^access-control-allow-origin: *\*' "$h" && ok "Access-Control-Allow-Origin" || ko "Access-Control-Allow-Origin"
grep -iq '^access-control-allow-methods: *.*' "$h" && ok "Access-Control-Allow-Methods" || ko "Access-Control-Allow-Methods"
grep -iq '^access-control-allow-headers: *.*' "$h" && ok "Access-Control-Allow-Headers" || ko "Access-Control-Allow-Headers"
grep -iq '^access-control-max-age: *.*' "$h" && ok "Access-Control-Max-Age" || ko "Access-Control-Max-Age"

# --- GET /api/notes?limit=3 (headers + body)
body="$tmpdir/list.json"; h="$tmpdir/list.h"
curl -fsS -D "$h" -o "$body" "$BASE/api/notes?limit=3"
grep -iq '^HTTP/.* 200' "$h" && ok "GET /api/notes 200" || ko "GET /api/notes 200"
grep -iq '^content-type: *application/json' "$h" && ok "CT json" || ko "CT json"
if grep -iq '^link: .*rel="next"' "$h"; then ok 'Link: next'; else ko 'Link: next'; fi

# --- POST /api/notes (JSON)
msg_json="test-suite json —— 1234567890 abcdefghij"
pj="$tmpdir/pj.json"
curl -fsS -H 'Content-Type: application/json' -d "{\"text\":\"${msg_json}\"}" "$BASE/api/notes" > "$pj" || true
python - <<PY && ok "publish JSON" || ko "publish JSON"
import json,sys
d=json.load(open("$pj","rb"))
assert isinstance(d,dict)
assert isinstance(d.get("id"),int)
assert d.get("text")==${msg_json!r}
PY

# --- POST /api/notes (FORM)
msg_form="form shim create"
pf="$tmpdir/pf.json"; h="$tmpdir/pf.h"
curl -sS -D "$h" -o "$pf" -d "text=${msg_form}" "$BASE/api/notes" || true
import_ok=$(python - <<PY || true
import json,sys
try:
  d=json.load(open("$pf","rb"))
  ok = isinstance(d,dict) and isinstance(d.get("id"),int) and d.get("text")==${msg_form!r}
  sys.exit(0 if ok else 1)
except Exception: sys.exit(1)
PY
)
if grep -qi '^HTTP/.* 20[01]' "$h" && [[ -n "$import_ok" ]]; then
  ok "publish FORM"
else
  ko "publish FORM"
fi

# --- negativos (id inexistente)
for kind in like view report; do
  code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/api/notes/999999/$kind")
  [[ "$code" == "404" ]] && ok "$kind 404" || ko "$kind 404"
done

echo
echo "RESUMEN: PASS=$pass FAIL=$fail"
[[ $fail -eq 0 ]]
