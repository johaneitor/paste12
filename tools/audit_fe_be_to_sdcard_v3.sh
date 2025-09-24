#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
. "$(dirname "$0")/_tmpdir.sh"
DEST(){ for d in "/sdcard/Download" "/storage/emulated/0/Download" "$HOME/Download" "$HOME/downloads"; do [ -d "$d" ] && [ -w "$d" ] && { echo "$d"; return; }; done; echo "$HOME"; }
TMPD="$(mkd)"; trap 'rm -rf "$TMPD"' EXIT
TS="$(date -u +%Y%m%d-%H%M%SZ)"; OUT="$(DEST)/fe-be-audit-$TS.txt"
{
  echo "base: $BASE"
  echo "== publish (FORM) =="; ID=$(curl -fsS -H 'Content-Type: application/x-www-form-urlencoded' --data-urlencode "text=fe-be $TS — 1234567890 abcdefghij" "$BASE/api/notes" | sed -n 's/.*"id":[ ]*\([0-9]\+\).*/\1/p'); echo "id=$ID"
  echo "== like/view =="; curl -sS -X POST "$BASE/api/notes/$ID/like"; echo; curl -sS -X POST "$BASE/api/notes/$ID/view"; echo
  echo "== single flags =="; H="$(curl -fsS "$BASE/?id=$ID&nosw=1&_=$TS")"
  echo "$H" | tr -d '\n' | grep -Fqi 'name="p12-single"' && echo "single: meta" || echo "$H" | tr -d '\n' | grep -Fqi 'data-single="1"' && echo "single: body" || echo "single: none"
} >"$OUT"
echo "OK: $OUT"
