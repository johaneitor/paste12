#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
pick(){ for d in "/sdcard/Download" "/storage/emulated/0/Download" "$HOME/Download" "$HOME/downloads"; do [ -d "$d" ] && [ -w "$d" ] && { echo "$d"; return; }; done; echo "$HOME"; }
DEST="$(pick)"; TS="$(date -u +%Y%m%d-%H%M%SZ)"
IDX="$DEST/index-$TS.html"; SUM="$DEST/frontend-audit-$TS.txt"
curl -fsS "$BASE/?nosw=1&_=$TS" -o "$IDX" || :
BYTES=$(wc -c < "$IDX" 2>/dev/null | tr -d ' ' || echo 0)
SCRIPTS=$(grep -aoi '<script' "$IDX" 2>/dev/null | wc -l | tr -d ' ')
oneline="$(tr -d '\n' < "$IDX" 2>/dev/null || echo)"
SHIM=$([ -n "$oneline" ] && echo "$oneline" | grep -Fqi 'name="p12-safe-shim"' && echo yes || echo no)
SINGLE=$([ -n "$oneline" ] && echo "$oneline" | grep -Fqi 'name="p12-single"' && echo yes || echo no)
{
  echo "== FE: index (sin SW) =="; echo "bytes=$BYTES"; echo "scripts=$SCRIPTS"
  echo "safe_shim=$SHIM"; echo "single_meta=$SINGLE"
  echo; echo "== Primeros 64 bytes =="; (command -v xxd >/dev/null && xxd -l 64 -g 1 "$IDX") || head -c 64 "$IDX" | od -An -t x1
} > "$SUM"
echo "OK: $IDX"; echo "OK: $SUM"
