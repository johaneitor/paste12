#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"

_red(){ printf "\033[31m%s\033[0m\n" "$*"; }
_yel(){ printf "\033[33m%s\033[0m\n" "$*"; }
_grn(){ printf "\033[32m%s\033[0m\n" "$*"; }

echo "== smoke_ui_pagination_expire @ $BASE =="

# Assets + firma LoadMore
for A in "/js/app.js" "/css/actions.css"; do
  code="$(curl -sS -I "$BASE$A" -o /dev/null -w '%{http_code}')" || code=000
  [[ "$code" == "200" || "$code" == "304" ]] || { _red "FAIL asset $A ($code)"; exit 1; }
done
js="$(curl -sS "$BASE/js/app.js")"
echo "$js" | grep -q 'p12SetupLoadMore' || { _red "FAIL: falta p12SetupLoadMore en app.js"; exit 1; }
_grn "OK assets + firma LoadMore"

# API básica
h="$(curl -sS "$BASE/api/health" | python -m json.tool 2>/dev/null || true)"
echo "$h" | grep -q '"ok": true' || { _red "FAIL /api/health"; echo "$h"; exit 1; }
routes="$(curl -sS "$BASE/api/_routes" | python -m json.tool 2>/dev/null || true)"
echo "$routes" | grep -q '/api/notes"' || { _red "FAIL: /api/_routes sin /api/notes"; exit 1; }
_grn "OK API básica"

# Helpers JSON (evitan arrays bash con espacios)
ids_line_from(){ BODY="$1" python - <<'PY'
import os, json
j=json.loads(os.environ["BODY"])
arr = j if isinstance(j, list) else j.get("items", [])
print(" ".join(str(x.get("id")) for x in arr if "id" in x))
PY
}
last_id_from(){ BODY="$1" python - <<'PY'
import os, json
j=json.loads(os.environ["BODY"])
arr = j if isinstance(j, list) else j.get("items", [])
print(arr[-1]["id"] if arr else "")
PY
}

# Seed mínimo para asegurar >10
for i in $(seq 1 5); do
  curl -sS -H 'Content-Type: application/json' \
    --data "{\"text\":\"seed $i $(date -u +%H:%M:%S)\",\"hours\":24}" \
    "$BASE/api/notes" >/dev/null || true
done

# Página 1
p1="$(curl -sS "$BASE/api/notes?active_only=1&limit=5&wrap=1")" || { _red "FAIL: no pude pedir p1"; exit 1; }
echo "$p1" | python -m json.tool >/dev/null 2>&1 || { _red "FAIL: p1 no es JSON"; echo "$p1"; exit 1; }
ids1="$(ids_line_from "$p1")"; last1="$(last_id_from "$p1")"
[[ -n "$ids1" && -n "$last1" ]] || { _red "FAIL: p1 sin ids o sin last"; echo "$p1"; exit 1; }
echo "p1 ids: $ids1  (before_id=$last1)"

# Página 2
p2="$(curl -sS "$BASE/api/notes?active_only=1&limit=5&wrap=1&before_id=$last1")" || { _red "FAIL: no pude pedir p2"; exit 1; }
echo "$p2" | python -m json.tool >/dev/null 2>&1 || { _red "FAIL: p2 no es JSON"; echo "$p2"; exit 1; }
ids2="$(ids_line_from "$p2")"
[[ -n "$ids2" ]] || { _red "FAIL: p2 vacía"; exit 1; }

# Sin solape
overlap="$(python - "$ids1" "$ids2" <<'PY'
import sys
s1=set(map(int, sys.argv[1].split()))
s2=set(map(int, sys.argv[2].split()))
print(len(s1 & s2))
PY
)"
[[ "$overlap" == "0" ]] || { _red "FAIL: solapamiento entre p1 y p2"; echo "p1:$ids1"; echo "p2:$ids2"; exit 1; }
_grn "OK paginación API (wrap + before_id)"

# Expiradas
exp="$(curl -sS -H 'Content-Type: application/json' \
  --data "{\"text\":\"expire-now $(date -u +%H:%M:%S)\",\"hours\":0}" "$BASE/api/notes")"
eid="$(BODY="$exp" python - <<'PY'
import os,json; print(json.loads(os.environ["BODY"]).get("id",""))
PY
)"
if [[ -z "${eid:-}" ]]; then
  _yel "WARN: no pude obtener ID de expirada (payload: $exp)"
else
  act="$(curl -sS "$BASE/api/notes?active_only=1&limit=50&wrap=1")"
  present="$(EID="$eid" BODY="$act" python - <<'PY'
import os,json
eid=os.environ.get("EID")
j=json.loads(os.environ["BODY"])
arr = j if isinstance(j,list) else j.get("items",[])
print(1 if any(str(x.get("id"))==str(eid) for x in arr) else 0)
PY
  )"
  [[ "$present" == "0" ]] || { _red "FAIL: expirada id=$eid aparece en active_only=1"; echo "$act" | head -c 600; exit 1; }
  _grn "OK expiradas: id=$eid NO aparece en activas"
fi

_grn "✅ smoke_ui_pagination_expire OK"
