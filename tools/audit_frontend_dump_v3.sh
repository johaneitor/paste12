#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }
source "$(dirname "$0")/_p12_common.sh"
DEST="$(pick_download)"; TS="$(stamp_utc)"
IDX="$DEST/index-$TS.html"; OUT="$DEST/frontend-audit-$TS.txt"

curl -fsS "$BASE/?nosw=1&_=$TS" -o "$IDX" || true
BYTES=$(wc -c < "$IDX" 2>/dev/null | tr -d ' ' || echo 0)
SCOUNT=$(grep -oi '<script' "$IDX" | wc -l | tr -d ' ' || echo 0)

{
  echo "base: $BASE"
  echo "== index dump =="
  echo "bytes=$BYTES"
  echo "scripts=$SCOUNT"
  echo "p12-safe-shim: $(grep -Fqi 'name=\"p12-safe-shim\"' "$IDX" && echo yes || echo no)"
  echo "p12-single (index base): $(grep -Fqi 'name=\"p12-single\"' "$IDX" && echo yes || echo no)"
  echo; echo "== hex head =="
  (command -v xxd >/dev/null && xxd -l 64 -g 1 "$IDX") || head -c 64 "$IDX" | od -An -t x1 || true
} > "$OUT" || true

echo "OK: $IDX"
echo "OK: $OUT"
