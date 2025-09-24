#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"

pick(){ for d in "/sdcard/Download" "/storage/emulated/0/Download" "$HOME/Download" "$HOME/downloads"; do [ -d "$d" ] && [ -w "$d" ] && { echo "$d"; return; }; done; echo "$HOME"; }
DEST="$(pick)"; TS="$(date -u +%Y%m%d-%H%M%SZ)"
TXT="$DEST/deploy-env-$TS.txt"
JSON="$DEST/deploy-env-$TS.json"

echo "base: $BASE" > "$TXT"

echo "== /api/deploy-stamp ==" >> "$TXT"
curl -fsS "$BASE/api/deploy-stamp" -H 'Accept: application/json' -o "$JSON" || true
BYTES="$(wc -c < "$JSON" 2>/dev/null | tr -d ' ' || echo 0)"
echo "json_bytes: $BYTES" >> "$TXT"

echo >> "$TXT"
echo "== /diag/import (Accept: json) ==" >> "$TXT"
curl -fsS -i "$BASE/diag/import" -H 'Accept: application/json' | sed -n '1,25p' >> "$TXT"

echo >> "$TXT"
echo "== /diag/import (?json=1) HEADERS ==" >> "$TXT"
curl -fsS -i "$BASE/diag/import?json=1" | sed -n '1,25p' >> "$TXT"

if [ "$BYTES" -gt 0 ]; then
  echo "OK: $JSON" >> "$TXT"
else
  echo "WARN: cuerpo JSON vacío; revisa P12_DIAG o el middleware" >> "$TXT"
fi

echo "OK: $TXT"
echo "OK: $JSON"
