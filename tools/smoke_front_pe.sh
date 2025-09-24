#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }
TMP="${TMPDIR:-$HOME/tmp}/pe.$$.html"; mkdir -p "${TMP%/*}"

echo "== GET /?pe=1 (HTML) =="
curl -fsSL --compressed "$BASE/?pe=1" -o "$TMP"
BYTES=$(wc -c < "$TMP" | tr -d ' ')
echo "bytes: $BYTES"
if grep -q 'id="pe-shim-p12"' "$TMP"; then
  echo "✓ shim presente en HTML"
else
  echo "✗ shim NO detectado"
fi
echo "== /api/notes quick check =="
curl -fsS "$BASE/api/notes?limit=3" | { command -v jq >/dev/null 2>&1 && jq '.items|length' || cat; } || true
echo "TMP: $TMP"
