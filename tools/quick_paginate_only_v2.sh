#!/usr/bin/env bash
set -Eeuo pipefail
BASE="${1:-http://127.0.0.1:8000}"
LIMIT="${2:-5}"

page_fetch() {
  local url="$1"
  local H="$(mktemp)" B="$(mktemp)"
  curl -sS -D "$H" -o "$B" "$url" >/dev/null
  {
    echo
    echo "— STATUS & HEADERS —"
    tr -d '\r' < "$H" | sed -n '1,/^$/p'
    echo
    echo "— BODY (primeras 800 chars) —"
    head -c 800 "$B"; echo
    local ctype
    ctype="$(sed -n '1,/^$/p' "$H" | awk -F': ' 'tolower($1)=="content-type"{print tolower($2)}')"
    if echo "$ctype" | grep -q 'application/json'; then
      python - <<PY
import io,json
try:
  with io.open("$B","r",encoding="utf-8") as f:
    data=json.load(f)
  print("OK JSON · len =", len(data))
  if data:
    ids=[d.get("id") for d in data]
    print("IDs:", ids[0], "…", ids[-1])
except Exception as e:
  print("JSON parse error:", e)
PY
    else
      echo "Content-Type no JSON: $ctype"
    fi
  } >&2
  tr -d '\r' < "$H" | awk -F': ' 'tolower($1)=="x-next-after"{print $2}' | tr -d '\r\n'
}

NEXT="$(page_fetch "$BASE/api/notes?limit=$LIMIT")"
[[ "$NEXT" =~ ^[0-9]+$ ]] || NEXT=""
[[ -n "$NEXT" ]] && echo "X-Next-After: $NEXT" >&2

while [ -n "${NEXT:-}" ]; do
  echo "➤ Siguiente página (after_id=$NEXT)" >&2
  NEXT="$(page_fetch "$BASE/api/notes?limit=$LIMIT&after_id=$NEXT")"
  [[ "$NEXT" =~ ^[0-9]+$ ]] || NEXT=""
  [[ -n "$NEXT" ]] && echo "X-Next-After: $NEXT" >&2
done
