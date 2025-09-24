#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
source "$(dirname "$0")/_tmpdir.sh"
D="$(mkd)"; trap 'rm -rf "$D"' EXIT
TS="$(date -u +%Y%m%d-%H%M%SZ)"
OUT="/sdcard/Download/fe-be-audit-$TS.txt"

new_note() {
  curl -fsS -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode "text=fe-be audit $TS — 1234567890 abcdefghij texto largo" \
    "$BASE/api/notes" | sed -n 's/.*"id":[ ]*\([0-9]\+\).*/\1/p'
}

ID="$(new_note || true)"

{
  echo "timestamp: $TS"
  echo "base: $BASE"
  echo
  echo "== publish (FORM) -> id = $ID =="
  echo
  if [ -n "$ID" ]; then
    echo "== like/view =="
    curl -sS -X POST "$BASE/api/notes/$ID/like" && echo
    curl -sS -X POST "$BASE/api/notes/$ID/view" && echo
    echo
    echo "== single flags (HTML) =="
    H="$(curl -fsS "$BASE/?id=$ID&nosw=1&_=$(date +%s)")"
    echo "$H" | tr -d '\n' | grep -Fqi '<meta name="p12-single"' && echo "single_meta: yes" || echo "single_meta: no"
    echo "$H" | tr -d '\n' | grep -Fqi 'data-single="1"'        && echo "single_body: yes" || echo "single_body: no"
    echo
    echo "share_url: $BASE/?id=$ID"
  else
    echo "No se pudo crear nota."
  fi
} > "$OUT"

echo "OK: $OUT"
