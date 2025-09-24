#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
OUT="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"

mkdir -p "$OUT"

SUM="$OUT/unified-audit-$TS.txt"
IDX="$OUT/index-$TS.html"
IDXH="$OUT/index-headers-$TS.txt"
HLT="$OUT/health-$TS.json"
OPT="$OUT/options-$TS.txt"
ANH="$OUT/api-notes-headers-$TS.txt"
ANB="$OUT/api-notes-$TS.json"

# 1) Health
curl -fsS "$BASE/api/health" -o "$HLT" || echo '{"ok":false}' > "$HLT"

# 2) OPTIONS (CORS)
curl -fsS -i -X OPTIONS "$BASE/api/notes" -o "$OPT" || true

# 3) GET /api/notes (headers + body)
curl -fsS -i "$BASE/api/notes?limit=10" -o "$ANH" || true
curl -fsS    "$BASE/api/notes?limit=10" -o "$ANB" || true

# 4) HTML raíz + headers
curl -fsS -D "$IDXH" "$BASE/?debug=1&nosw=1&v=$(date +%s)" -o "$IDX" || true

# 5) Checks rápidos en HTML
HEAD_OK=$(grep -c -i "<head" "$IDX" 2>/dev/null || echo 0)
VIEWS_OK=$(grep -c 'class="views"' "$IDX" 2>/dev/null || echo 0)
ADS_HEAD=$(grep -ci 'adsbygoogle\.js' "$IDX" 2>/dev/null || echo 0)
ADS_CLIENT=$(grep -ci 'data-ad-client="ca-pub-' "$IDX" 2>/dev/null || echo 0)

# 6) Resumen legible
{
  echo "== Unified audit (factory-v2) =="
  echo "base: $BASE"
  echo "ts  : $TS"
  echo
  echo "-- health --"
  cat "$HLT" 2>/dev/null || true
  echo
  echo "-- OPTIONS /api/notes --"
  sed -n '1,12p' "$OPT" 2>/dev/null || true
  echo
  echo "-- GET /api/notes (headers) --"
  sed -n '1,20p' "$ANH" 2>/dev/null || true
  echo
  echo "-- GET /api/notes (body first 1k) --"
  head -c 1024 "$ANB" 2>/dev/null || true
  echo
  echo "-- index.html quick checks --"
  echo "HEAD tag     : $HEAD_OK"
  echo ".views span  : $VIEWS_OK"
  echo "AdSense <script> in HEAD : $ADS_HEAD"
  echo "AdSense data-ad-client    : $ADS_CLIENT"
  echo
  echo "== Files =="
  echo "  $HLT"
  echo "  $OPT"
  echo "  $ANH"
  echo "  $ANB"
  echo "  $IDX"
  echo "  $IDXH"
  echo "== END =="
} > "$SUM"

echo "Resumen: $SUM"
