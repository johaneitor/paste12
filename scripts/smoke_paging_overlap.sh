#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
_red(){ printf "\033[31m%s\033[0m\n" "$*"; }
_grn(){ printf "\033[32m%s\033[0m\n" "$*"; }

ids_line_from(){ BODY="$1" python - <<'PY'
import os,json
j=json.loads(os.environ["BODY"])
arr = j if isinstance(j,list) else j.get("items", [])
print(" ".join(str(x.get("id")) for x in arr if "id" in x))
PY
}
last_id_from(){ BODY="$1" python - <<'PY'
import os,json
j=json.loads(os.environ["BODY"])
arr = j if isinstance(j,list) else j.get("items", [])
print(arr[-1]["id"] if arr else "")
PY
}

echo "== smoke_paging_overlap @ $BASE =="

p1="$(curl -sS "$BASE/api/notes?active_only=1&limit=5&wrap=1")"
ids1="$(ids_line_from "$p1")"; last1="$(last_id_from "$p1")"
[[ -n "$ids1" && -n "$last1" ]] || { _red "FAIL: p1 vacía o sin last"; echo "$p1"; exit 1; }
echo "p1: $ids1  (before_id=$last1)"

p2="$(curl -sS "$BASE/api/notes?active_only=1&limit=5&wrap=1&before_id=$last1")"
ids2="$(ids_line_from "$p2")"
[[ -n "$ids2" ]] || { _red "FAIL: p2 vacía"; echo "$p2"; exit 1; }
echo "p2: $ids2"

overlap="$(python - "$ids1" "$ids2" <<'PY'
import sys
s1=set(map(int, sys.argv[1].split()))
s2=set(map(int, sys.argv[2].split()))
print(len(s1 & s2))
PY
)"
[[ "$overlap" == "0" ]] || { _red "FAIL: solapamiento entre p1 y p2"; exit 1; }

_grn "✅ OK: sin solapamiento; before_id aplicado"
