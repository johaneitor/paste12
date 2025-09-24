#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }
TMP="${TMPDIR:-/tmp}/pub.$$.tmp"; mkdir -p "${TMP%/*}"

test_case() {
  local name="$1"; shift
  echo "---- $name ----"
  curl -sS -D "$TMP.h" -o "$TMP.b" "$@" || true
  sed -n '1,20p' "$TMP.h"
  cat "$TMP.b"
  echo
}

TS="$(date -u +%H:%M:%SZ)"
TXT="debug publish ${TS} — abcdefghij 1234567890 texto suficientemente largo"

printf '%s' "{\"text\":\"$TXT\"}" > "$TMP.json"
printf '%s' "$TXT" > "$TMP.txt"

# A) JSON estándar
test_case "JSON std" -H 'Content-Type: application/json' -H 'Accept: application/json' \
  --data-binary @"$TMP.json" "$BASE/api/notes"

# B) JSON con charset
test_case "JSON utf-8" -H 'Content-Type: application/json; charset=utf-8' -H 'Accept: application/json' \
  --data-binary @"$TMP.json" "$BASE/api/notes"

# C) FORM urlencoded
test_case "FORM urlencoded" -H 'Content-Type: application/x-www-form-urlencoded' -H 'Accept: application/json' \
  --data-urlencode "text=$TXT" "$BASE/api/notes"

# D) texto puro (por si tu server lo tolera)
test_case "text/plain (best effort)" -H 'Content-Type: text/plain' -H 'Accept: application/json' \
  --data-binary @"$TMP.txt" "$BASE/api/notes"
