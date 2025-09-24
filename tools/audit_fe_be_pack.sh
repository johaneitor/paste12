#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
pick(){ for d in "/sdcard/Download" "/storage/emulated/0/Download" "$HOME/Download" "$HOME/downloads"; do [ -d "$d" ] && [ -w "$d" ] && { echo "$d"; return; }; done; echo "$HOME"; }
DEST="$(pick)"; TS="$(date -u +%Y%m%d-%H%M%SZ)"
IDX="$DEST/index-$TS.html"; SUM="$DEST/frontend-overview-$TS.md"; BKA="$DEST/backend-audit-$TS.txt"

# index sin SW
curl -fsS "$BASE/?nosw=1&_=$TS" -o "$IDX" || echo "<!-- fetch failed -->" > "$IDX"

# sumario FE
BYTES=$(wc -c < "$IDX" 2>/dev/null | tr -d ' ' || echo 0)
SCOUNT=$(grep -oi '<script' "$IDX" | wc -l | tr -d ' ' || echo 0)
{
  echo "# FE Overview — $TS"
  echo "- bytes: $BYTES"
  echo "- <script> tags: $SCOUNT"
  echo "- looks_404: $(grep -qi '<title>404 Not Found' \"$IDX\" && echo yes || echo no)"
  echo "- has p12-safe-shim: $(grep -qi 'name=\"p12-safe-shim\"' \"$IDX\" && echo yes || echo no)"
} > "$SUM"

# BE rápido
{
  echo "[health]"; curl -sS "$BASE/api/health"; echo
  echo "[preflight]"; curl -sS -i -X OPTIONS "$BASE/api/notes" | sed -n '1,20p'
  echo "[list head]"; curl -sS -i "$BASE/api/notes?limit=5" | sed -n '1,20p'
} > "$BKA"

echo "OK: $IDX"
echo "OK: $SUM"
echo "OK: $BKA"
