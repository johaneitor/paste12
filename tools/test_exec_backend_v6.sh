#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://tu-app.onrender.com}"

_red(){ printf "\e[31m%s\e[0m\n" "$*"; }
_grn(){ printf "\e[32m%s\e[0m\n" "$*"; }
_yel(){ printf "\e[33m%s\e[0m\n" "$*"; }

fail=0

# 1) health (JSON {"ok":true})
hb="$(curl -fsS "$BASE/api/health" || true)"
if [ "$hb" = '{"ok": true}' ] || [ "$hb" = '{"ok":true}' ]; then
  _grn "OK  - health body JSON"
else
  _red "FAIL- health body: $hb"; fail=$((fail+1))
fi

# 2) CORS preflight en /api/notes
h="$(curl -i -fsS -X OPTIONS "$BASE/api/notes" | sed -n '1,20p')"
grep -q "^HTTP/.* 204" <<<"$h"        && _grn "OK  - OPTIONS 204" || { _red "FAIL- OPTIONS 204"; fail=$((fail+1)); }
grep -qi "^Access-Control-Allow-Methods: .*GET,POST,OPTIONS" <<<"$h" && _grn "OK  - ACAM" || { _red "FAIL- ACAM"; fail=$((fail+1)); }
grep -qi "^Access-Control-Allow-Headers: .*Content-Type" <<<"$h"     && _grn "OK  - ACAH" || { _red "FAIL- ACAH"; fail=$((fail+1)); }
grep -qi "^Access-Control-Max-Age: .*" <<<"$h"                        && _grn "OK  - Max-Age" || { _red "FAIL- Max-Age"; fail=$((fail+1)); }

# 3) GET /api/notes (200 + JSON + Link)
resp="$(mktemp)"; hdr="$(mktemp)"
curl -fsS -D "$hdr" "$BASE/api/notes?limit=3" -o "$resp"
ct="$(grep -i '^Content-Type:' "$hdr" | tr -d '\r')"
grep -q '"id"' "$resp" && _grn "OK  - GET /api/notes 200" || { _red "FAIL- GET /api/notes"; fail=$((fail+1)); }
grep -qi 'application/json' <<<"$ct" && _grn "OK  - CT json" || { _red "FAIL- CT json"; fail=$((fail+1)); }
grep -qi '^Link:' "$hdr" && _grn "OK  - Link: next" || { _red "FAIL- Link: next"; fail=$((fail+1)); }

# 4) POST JSON
nid_json="$(curl -fsS -H 'Content-Type: application/json' -d '{"text":"test-suite json —— 1234567890 abcdefghij"}' "$BASE/api/notes" \
  | python - <<'PY'
import json,sys
try:
    d=json.load(sys.stdin); print(d.get("id") or "")
except Exception: print("")
PY
)"
if [ -n "${nid_json:-}" ]; then _grn "OK  - publish JSON id=$nid_json"; else _red "FAIL- publish JSON"; fail=$((fail+1)); fi

# 5) POST FORM (debe crear y devolver JSON con id)
nid_form="$(curl -fsS -H 'Content-Type: application/x-www-form-urlencoded' -d "text=form suite $(date +%s)" "$BASE/api/notes" \
  | python - <<'PY'
import json,sys
try:
    d=json.load(sys.stdin); print(d.get("id") or "")
except Exception: print("")
PY
)"
if [ -n "${nid_form:-}" ]; then _grn "OK  - publish FORM id=$nid_form"; else _red "FAIL- publish FORM"; fail=$((fail+1)); fi

# 6) like (debe 200 y ok:true)
if [ -n "${nid_form:-}" ]; then
  lk="$(curl -fsS -X POST "$BASE/api/notes/$nid_form/like" | grep -o '"ok": *true' || true)"
  [ -n "$lk" ] && _grn "OK  - like" || { _yel "info: like no implementado/ok ausente (tolerado)"; }
fi

echo
if [ "$fail" -eq 0 ]; then
  _grn "RESUMEN: OK (todo verde)"
  exit 0
else
  _red "RESUMEN: $fail fallas"
  exit 1
fi
