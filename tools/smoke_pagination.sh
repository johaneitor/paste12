#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
_red(){ printf "\033[31m%s\033[0m\n" "$*"; }
_grn(){ printf "\033[32m%s\033[0m\n" "$*"; }
echo "== smoke_pagination @ $BASE =="

for i in 1 2 3; do
  curl -sS -H 'Content-Type: application/json' --data "{\"text\":\"pg smoke $i\",\"hours\":24}" "$BASE/api/notes" >/dev/null
done

P1="$(curl -sS "$BASE/api/notes?wrap=1&active_only=1&limit=2")"
echo "$P1" | grep -q '"items"' || { _red "wrap=1 no devuelve items"; printf "%s\n" "$P1"; exit 1; }
read -r -a IDS1 <<<"$(BODY="$P1" python - <<'PY'
import os, json
j=json.loads(os.environ['BODY'])
print(*[str(x['id']) for x in j['items']])
PY
)"
[[ ${#IDS1[@]} -ge 1 ]] || { _red "página 1 vacía"; exit 1; }
MIN1="${IDS1[-1]}"

P2="$(curl -sS "$BASE/api/notes?wrap=1&active_only=1&limit=2&before_id=$MIN1")"
read -r -a IDS2 <<<"$(BODY="$P2" python - <<'PY'
import os, json
j=json.loads(os.environ['BODY'])
print(*[str(x['id']) for x in j.get('items',[])])
PY
)"

# comprobar que no hay superposición
for id in "${IDS1[@]}"; do
  if printf "%s\n" "${IDS2[@]}" | grep -qx "$id"; then
    _red "superposición entre páginas: $id"
    exit 1
  fi
done

_grn "✅ smoke_pagination OK (p1=${IDS1[*]} / p2=${IDS2[*]})"
