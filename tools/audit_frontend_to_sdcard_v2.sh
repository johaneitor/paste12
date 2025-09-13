#!/usr/bin/env bash
set -euo pipefail
export TMPDIR="${TMPDIR:-$HOME/tmp}"; mkdir -p "$TMPDIR"

BASE="${1:-https://paste12-rmsk.onrender.com}"
pick(){ for d in "/sdcard/Download" "/storage/emulated/0/Download" "$HOME/Download" "$HOME/downloads"; do [ -d "$d" ] && [ -w "$d" ] && { echo "$d"; return; }; done; echo "$HOME"; }
DEST="$(pick)"; TS="$(date -u +%Y%m%d-%H%M%SZ)"
IDX="$DEST/index-$TS.html"; SUM="$DEST/frontend-overview-$TS.md"

curl -fsS "$BASE/?nosw=1&_=$TS" -o "$IDX" || : 
BYTES=$(wc -c < "$IDX" 2>/dev/null | tr -d ' ' || echo 0)
SCOUNT=$(grep -oiF '<script' "$IDX" | wc -l | tr -d ' ' || echo 0)

{
  echo "# Frontend Overview — $TS"
  echo "- bytes: $BYTES"
  echo "- <script> tags: $SCOUNT"
  echo "- has p12-safe-shim: $(grep -qiF 'name=\"p12-safe-shim\"' "$IDX" && echo yes || echo no)"
  echo "- has p12-single: $(grep -qiF 'name=\"p12-single\"' "$IDX" && echo yes || echo no)"
} > "$SUM"

echo "OK: $IDX"
echo "OK: $SUM"
