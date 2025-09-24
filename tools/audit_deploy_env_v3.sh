#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }

pick(){ for d in "/sdcard/Download" "/storage/emulated/0/Download" "$HOME/Download" "$HOME/downloads"; do [ -d "$d" ] && [ -w "$d" ] && { echo "$d"; return; }; done; echo "$HOME"; }
DEST="$(pick)"; TS="$(date -u +%Y%m%d-%H%M%SZ)"
TXT="$DEST/deploy-env-$TS.txt"
JSON="$DEST/deploy-env-$TS.json"

# Retries agradables
retry() { local n=0; local max=5; local delay=1; while true; do "$@" && return 0 || { n=$((n+1)); [ $n -ge $max ] && return 1; sleep $delay; delay=$((delay*2)); }; done; }

# 1) Cabecera + contenido JSON del stamp
{
  echo "base: $BASE"
  echo "== /api/deploy-stamp (HEADERS) =="
  retry curl -fsS -i "$BASE/api/deploy-stamp" | sed -n '1,20p'
  echo
  echo "== contenido JSON (primeras 200) =="
  retry curl -fsS "$BASE/api/deploy-stamp" | dd bs=1 count=200 2>/dev/null || true
} > "$TXT" || true

# 2) JSON crudo (si hay respuesta, no quedará en 0 bytes)
retry curl -fsS "$BASE/api/deploy-stamp" -o "$JSON" || echo '{}' > "$JSON"

echo "OK: $TXT"
echo "OK: $JSON"
