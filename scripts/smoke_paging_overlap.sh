#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"

_red(){ printf "\033[31m%s\033[0m\n" "$*"; }
_grn(){ printf "\033[32m%s\033[0m\n" "$*"; }

req() {
  # req METHOD URL -> sets LAST_CODE, LAST_CT, LAST_HDRS, LAST_BODY
  local method="$1" url="$2"; shift 2 || true
  local tmpb tmph
  tmpb="$(mktemp)"; tmph="$(mktemp)"
  LAST_CODE="$(curl -sS -X "$method" -H 'Accept: application/json' -D "$tmph" -o "$tmpb" -w '%{http_code}' "$url" || echo 000)"
  LAST_BODY="$(cat "$tmpb")"
  LAST_HDRS="$(cat "$tmph")"
  LAST_CT="$(printf '%s\n' "$LAST_HDRS" | tr -d '\r' | awk -F': ' 'tolower($1)=="content-type"{print tolower($2)}' | head -n1)"
  rm -f "$tmpb" "$tmph"
}

must_json() {
  if [[ "$LAST_CODE" != 200 ]]; then
    _red "FAIL: $1 -> HTTP $LAST_CODE"
    printf -- "---- headers ----\n%s\n---- body (head) ----\n" "$LAST_HDRS"
    printf "%s\n" "$LAST_BODY" | sed -n '1,40p'
    exit 1
  fi
  if [[ "$LAST_CT" != application/json* ]]; then
    _red "FAIL: $1 no devolvió JSON (Content-Type='$LAST_CT')"
    printf -- "---- headers ----\n%s\n---- body (head) ----\n" "$LAST_HDRS"
    printf "%s\n" "$LAST_BODY" | sed -n '1,40p'
    exit 1
  fi
}

ids_line_from(){ BODY="$1" python - <<'PY'
import os, json
j=json.loads(os.environ["BODY"])
arr = j if isinstance(j, list) else j.get("items", [])
print(" ".join(str(x.get("id")) for x in arr if isinstance(x,dict) and "id" in x))
PY
}

last_id_from(){ BODY="$1" python - <<'PY'
import os, json
j=json.loads(os.environ["BODY"])
arr = j if isinstance(j, list) else j.get("items", [])
print(arr[-1]["id"] if arr else "")
PY
}

echo "== smoke_paging_overlap @ $BASE =="

# Sanity: health
req GET "$BASE/api/health"; must_json "/api/health"

# Página 1
req GET "$BASE/api/notes?active_only=1&limit=5&wrap=1"
must_json "/api/notes p1"
p1="$LAST_BODY"
ids1="$(ids_line_from "$p1")"; last1="$(last_id_from "$p1")"
[[ -n "$ids1" && -n "$last1" ]] || { _red "FAIL: p1 vacía o sin last"; echo "$p1" | python -m json.tool || echo "$p1"; exit 1; }
echo "p1: $ids1  (before_id=$last1)"

# Página 2 (before_id = último de p1)
req GET "$BASE/api/notes?active_only=1&limit=5&wrap=1&before_id=$last1"
must_json "/api/notes p2"
p2="$LAST_BODY"
ids2="$(ids_line_from "$p2")"
[[ -n "$ids2" ]] || { _red "FAIL: p2 vacía"; echo "$p2" | python -m json.tool || echo "$p2"; exit 1; }
echo "p2: $ids2"

# Sin solapamiento
overlap="$(python - "$ids1" "$ids2" <<'PY'
import sys
s1=set(map(int, sys.argv[1].split()))
s2=set(map(int, sys.argv[2].split()))
print(len(s1 & s2))
PY
)"
[[ "$overlap" == "0" ]] || { _red "FAIL: solapamiento entre p1 y p2"; exit 1; }

_grn "✅ OK: sin solapamiento; before_id aplicado"
