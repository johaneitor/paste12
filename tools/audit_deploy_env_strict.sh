#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }
pick(){ for d in "/sdcard/Download" "/storage/emulated/0/Download" "$HOME/Download" "$HOME/downloads"; do [ -d "$d" ] && [ -w "$d" ] && { echo "$d"; return; }; done; echo "$HOME"; }
DEST="$(pick)"; TS="$(date -u +%Y%m%d-%H%M%SZ)"
TXT="$DEST/deploy-env-$TS.txt"; JSON="$DEST/deploy-env-$TS.json"
echo "base: $BASE" > "$TXT"; echo "== /api/deploy-stamp ==" >> "$TXT"
curl -fsS "$BASE/api/deploy-stamp" -o "$JSON" || true
BYTES=$(wc -c < "$JSON" | tr -d ' '); echo "json_bytes: $BYTES" >> "$TXT"
[ "$BYTES" -eq 0 ] && { echo "ERROR: deploy-stamp vacío" >> "$TXT"; echo "✗ deploy-stamp vacío"; exit 2; }
head -n1 "$JSON" >> "$TXT"; echo "OK: $TXT"; echo "OK: $JSON"
