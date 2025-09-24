#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }
source "$(dirname "$0")/_p12_common.sh"
DEST="$(pick_download)"; TS="$(stamp_utc)"; OUT="$DEST/fe-be-audit-$TS.txt"

{
  echo "base: $BASE"
  echo "== publish FORM =="
  ID=$(curl -fsS -H 'Content-Type: application/x-www-form-urlencoded' \
        --data-urlencode "text=fe-be $(date -u +%H:%M:%SZ) —— 1234567890 abcdefghij" \
        "$BASE/api/notes" | sed -n 's/.*"id":[ ]*\([0-9]\+\).*/\1/p'); echo "id=$ID"

  echo; echo "== like/view =="
  curl -sS -X POST "$BASE/api/notes/$ID/like"; echo
  curl -sS -X POST "$BASE/api/notes/$ID/view"; echo

  echo; echo "== single flags (HTML) =="
  H="$(curl -fsS "$BASE/?id=$ID&nosw=1&_=$(date +%s)")"
  if echo "$H" | tr -d '\n' | grep -Fqi '<meta name="p12-single"'; then
    echo "OK meta p12-single"
  elif echo "$H" | tr -d '\n' | grep -Fqi 'data-single=\"1\"'; then
    echo "OK body data-single"
  else
    echo "X sin single flag"
  fi
} > "$OUT" || true

echo "OK: $OUT"
