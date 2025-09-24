#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
_red(){ printf "\033[31m%s\033[0m\n" "$*"; }
_grn(){ printf "\033[32m%s\033[0m\n" "$*"; }

echo "== smoke_load_more @ $BASE =="
# assets
for A in "/js/app.js" "/css/actions.css"; do
  code="$(curl -sS -I "$BASE$A" -o /dev/null -w '%{http_code}')" || code=000
  [[ "$code" == "200" || "$code" == "304" ]] || { _red "FAIL asset $A ($code)"; exit 1; }
done
# firma en app.js
curl -sS "$BASE/js/app.js" | grep -q 'p12SetupLoadMore' || { _red "FAIL: p12SetupLoadMore no está en app.js"; exit 1; }

# Semilla para tener >20
for i in $(seq 1 5); do
  curl -sS -H 'Content-Type: application/json' --data "{\"text\":\"seed $i\",\"hours\":24}" "$BASE/api/notes" >/dev/null
done

# Verificación API de paginado (wrap o array)
p1="$(curl -sS "$BASE/api/notes?active_only=1&limit=2&wrap=1")"
ids1=($(BODY="$p1" python - <<'PY'
import os,json,sys
j=json.loads(os.environ["BODY"])
if isinstance(j,list):
  print(*[x["id"] for x in j])
else:
  print(*[x["id"] for x in j.get("items",[])])
PY
))
[[ ${#ids1[@]} -ge 1 ]] || { _red "FAIL: página 1 vacía"; exit 1; }
_grn "✅ smoke_load_more OK (app.js+API listas)"
