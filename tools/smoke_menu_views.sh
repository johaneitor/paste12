#!/usr/bin/env bash
set -euo pipefail

BASE="${1:-https://paste12-rmsk.onrender.com}"

_red(){ printf "\033[31m%s\033[0m\n" "$*"; }
_grn(){ printf "\033[32m%s\033[0m\n" "$*"; }
_yel(){ printf "\033[33m%s\033[0m\n" "$*"; }

LAST_CODE=0
LAST_BODY=""

req() {
  local method="$1" url="$2" data="${3:-}"
  local tmp; tmp="$(mktemp)"
  if [[ -n "$data" ]]; then
    LAST_CODE="$(curl -sS -X "$method" -H 'Content-Type: application/json' --data "$data" -o "$tmp" -w '%{http_code}' "$url")"
  else
    LAST_CODE="$(curl -sS -X "$method" -o "$tmp" -w '%{http_code}' "$url")"
  fi
  LAST_BODY="$(cat "$tmp")"
  rm -f "$tmp"
}

pp(){ echo "$LAST_BODY" | python -m json.tool 2>/dev/null || echo "$LAST_BODY"; }

need_code() {
  local want="$1" msg="${2:-}"
  if [[ "$LAST_CODE" != "$want" ]]; then
    _red "FAIL $msg (got $LAST_CODE)"
    echo "Body:"; echo "$LAST_BODY"
    exit 1
  fi
}

json_get() {
  local key="$1"
  BODY="$LAST_BODY" python - "$key" <<'PY'
import os, sys, json
key = sys.argv[1]
j = json.loads(os.environ["BODY"])
cur = j
for part in key.split('.'):
    if isinstance(cur, list):
        cur = cur[int(part)]
    else:
        cur = cur.get(part)
print("" if cur is None else cur)
PY
}

check_routes() {
  BODY="$LAST_BODY" python - <<'PY' || exit 1
import os, json, sys
data = json.loads(os.environ["BODY"])
rules = [r.get("rule") for r in data.get("routes",[])]
required = [
  "/api/notes",
  "/api/notes/<int:note_id>",
  "/api/notes/<int:note_id>/view",
  "/api/notes/<int:note_id>/like",
  "/api/notes/<int:note_id>/report",
]
missing = [x for x in required if x not in rules]
if missing:
  print("MISSING:", ", ".join(missing)); sys.exit(1)
print("OK")
PY
}

echo "== smoke_menu_views @ $BASE =="

echo "-- assets: HEAD /css/actions.css --"
code_css="$(curl -sS -I "$BASE/css/actions.css" -o /dev/null -w '%{http_code}')"
[[ "$code_css" == "200" || "$code_css" == "304" ]] || { _red "FAIL assets css ($code_css)"; exit 1; }
_grn "ok"

echo "-- assets: HEAD /js/actions.js --"
code_js="$(curl -sS -I "$BASE/js/actions.js" -o /dev/null -w '%{http_code}')"
[[ "$code_js" == "200" || "$code_js" == "304" ]] || { _red "FAIL assets js ($code_js)"; exit 1; }
_grn "ok"

echo "-- sanity: grep en /js/actions.js (note-menu / deriveId / DOMContentLoaded) --"
js="$(curl -sS "$BASE/js/actions.js")"
echo "$js" | grep -q 'note-menu'        || { _red "FAIL: no 'note-menu'"; exit 1; }
echo "$js" | grep -q 'function deriveId' || { _red "FAIL: no deriveId()"; exit 1; }
echo "$js" | grep -q 'DOMContentLoaded'  || { _red "FAIL: no DOMContentLoaded"; exit 1; }
_grn "ok"

echo "-- API: GET /api/health --"
req GET "$BASE/api/health"; need_code 200 "health"; pp

echo "-- API: /__api_import_error (404 esperado) --"
req GET "$BASE/__api_import_error"
if [[ "$LAST_CODE" == "404" ]]; then _grn "ok"; else _yel "WARN: __api_import_error=$LAST_CODE"; fi

echo "-- API: /__whoami (hint) --"
req GET "$BASE/__whoami"
if [[ "$LAST_CODE" == "200" ]]; then
  echo "$LAST_BODY" | grep -q '"api"' || _yel "WARN: blueprint 'api' no listado"
  echo "$LAST_BODY" | grep -q '"has_detail_routes": true' || _yel "WARN: has_detail_routes != true (no detiene)"
else
  _yel "WARN: __whoami -> $LAST_CODE"
fi

echo "-- API: /api/_routes incluye endpoints de notas --"
req GET "$BASE/api/_routes"; need_code 200 "_routes"
check_routes || { _red "FAIL: faltan endpoints en /api/_routes"; pp; exit 1; }
_grn "ok"

echo "-- create note (POST /api/notes) --"
payload="$(printf '{"text":"smoke menu+views %s","hours":24}' "$(date -u +%Y-%m-%dT%H:%M:%SZ)")"
req POST "$BASE/api/notes" "$payload"; need_code 201 "create"; pp
ID="$(json_get id)"; [[ -n "$ID" ]] || { _red "FAIL: no pude extraer id"; exit 1; }
echo "ID=$ID"

echo "-- POST /api/notes/$ID/view --"
req POST "$BASE/api/notes/$ID/view"; need_code 200 "view"; pp

echo "-- POST /api/notes/$ID/report --"
req POST "$BASE/api/notes/$ID/report"; need_code 200 "report"; pp

echo "-- POST /api/notes/$ID/like --"
req POST "$BASE/api/notes/$ID/like"; need_code 200 "like"; pp

echo "-- GET /api/notes/$ID (ver contadores) --"
req GET "$BASE/api/notes/$ID"; need_code 200 "get one"; pp
V="$(json_get views)"; L="$(json_get likes)"; R="$(json_get reports)"
echo "V=$V L=$L R=$R"
[[ "$V" =~ ^[0-9]+$ && "$V" -ge 1 ]] || { _red "FAIL: views no >=1"; exit 1; }
[[ "$L" =~ ^[0-9]+$ && "$L" -ge 1 ]] || { _red "FAIL: likes no >=1"; exit 1; }
[[ "$R" =~ ^[0-9]+$ && "$R" -ge 1 ]] || { _red "FAIL: reports no >=1"; exit 1; }

_grn "✅ smoke_menu_views OK (ID=$ID)"
