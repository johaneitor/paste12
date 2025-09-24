#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }

run(){
  local name="$1" url="$2" meth="${3:-GET}" hdr="${4:-}"
  echo "== $name =="
  TMP="$(mktemp)"; trap 'rm -f "$TMP"' RETURN
  if [ -n "$hdr" ]; then
    curl -sS -D headers.txt -X "$meth" -H "$hdr" "$url" -o "$TMP"
  else
    curl -sS -D headers.txt -X "$meth" "$url" -o "$TMP"
  fi
  sed -n '1,30p' headers.txt
  echo "body_size=$(wc -c < "$TMP" | tr -d ' ')"
  (command -v xxd >/dev/null && xxd -l 64 -g 1 "$TMP") || head -c 64 "$TMP" | od -An -t x1 || true
  echo
}

run "GET simple"              "$BASE/diag/import"
run "GET + Accept:json"       "$BASE/diag/import" GET "Accept: application/json"
run "GET ?json=1"             "$BASE/diag/import?json=1"
run "POST vacío"              "$BASE/diag/import" POST
