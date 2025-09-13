#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }
pick_dest(){ for d in "$HOME/Download" "$HOME/downloads" "/sdcard/Download" "/storage/emulated/0/Download"; do [ -d "$d" ] && [ -w "$d" ] && { echo "$d"; return; }; done; mkdir -p "$HOME/downloads"; echo "$HOME/downloads"; }
DEST="$(pick_dest)"; TS="$(date -u +%Y%m%d-%H%M%SZ)"
IDX="$DEST/index-$TS.html"; SUM="$DEST/frontend-overview-$TS.txt"; BKA="$DEST/backend-audit-$TS.txt"
echo "== save index =="; curl -fsS "$BASE/?nosw=1&_=$TS" -o "$IDX" || echo "<!-- fetch failed -->" > "$IDX"
echo "== sum frontend ==" > "$SUM"
echo "bytes: $(wc -c < "$IDX" | tr -d ' ')" >> "$SUM"
echo "scripts: $(grep -oi '<script' "$IDX" | wc -l | tr -d ' ')" >> "$SUM"
echo "marker v7: $(grep -qi 'name=\"p12-v7\"' "$IDX" && echo yes || echo no)" >> "$SUM"
echo "== backend quick ==" > "$BKA"
echo "[health]" >> "$BKA"; curl -sS "$BASE/api/health" >> "$BKA" || true; echo >> "$BKA"
echo "[preflight]" >> "$BKA"; curl -sS -i -X OPTIONS "$BASE/api/notes" | sed -n '1,20p' >> "$BKA" || true
echo "OK: $IDX"; echo "OK: $SUM"; echo "OK: $BKA"
