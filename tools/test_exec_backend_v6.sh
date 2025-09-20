#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -z "$BASE" ] && { echo "Uso: $0 https://tu-app.onrender.com"; exit 1; }
pass=0; fail=0
chk(){ if eval "$1"; then echo "OK  - $2"; pass=$((pass+1)); else echo "FAIL- $2"; fail=$((fail+1)); fi; }

# health (txt)  — ¡sin quotes literales!
hb="$(curl -fsS "$BASE/api/health" || true)"
chk "[[ \"$hb\" == \"health ok\" ]]" "health body: health ok"

# OPTIONS /api/notes → 204 + CORS
headers="$(curl -sSI -X OPTIONS "$BASE/api/notes")"
chk "grep -q '^HTTP/.* 204' <<<\"$headers\"" "OPTIONS 204"
chk "grep -qi '^Access-Control-Allow-Methods: .*GET,POST,OPTIONS' <<<\"$headers\"" "ACAM"
chk "grep -qi '^Access-Control-Allow-Headers: .*Content-Type' <<<\"$headers\"" "ACAH"
chk "grep -qi '^Access-Control-Max-Age: *86400' <<<\"$headers\"" "Max-Age"

# GET /api/notes con Link
rh="$(curl -sSI "$BASE/api/notes?limit=3")"
chk "grep -q '^HTTP/.* 200' <<<\"$rh\"" "GET /api/notes 200"
chk "grep -qi '^content-type: *application/json' <<<\"$rh\"" "CT json"
chk "grep -qi '^Link: .*rel=\"next\"' <<<\"$rh\"" "Link: next"

# POST form → crea (cuidado con quoting)
st="$(curl -sS -o /dev/null -w '%{http_code}' -d 'text=hola hola shim' "$BASE/api/notes")"
chk "[[ \"$st\" == \"200\" ]]" "publish FORM -> 200"

# Crear para like/view
nid="$(curl -fsS -H 'Content-Type: application/json' -d '{"text":"shim test likeview"}' "$BASE/api/notes" | python - <<'PY'
import sys, json; print(json.load(sys.stdin)["id"])
PY
)"
chk "curl -fsS -X POST \"$BASE/api/notes/$nid/like\" >/dev/null" "like 200"
chk "curl -fsS -X POST \"$BASE/api/notes/$nid/view\" >/dev/null" "view 200"

# Negativos esperados
chk "[[ \$(curl -sS -o /dev/null -w '%{http_code}' -X POST \"$BASE/api/notes/999999/like\") == 404 ]]" "like 404"
chk "[[ \$(curl -sS -o /dev/null -w '%{http_code}' -X POST \"$BASE/api/notes/999999/view\") == 404 ]]" "view 404"
chk "[[ \$(curl -sS -o /dev/null -w '%{http_code}' -X POST \"$BASE/api/notes/999999/report\") == 404 ]]" "report 404"

echo; echo "RESUMEN: PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] || exit 1
