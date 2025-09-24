#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
OUT="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
mkdir -p "$OUT"

echo "== FE/BE quick smoke v1 =="
echo "BASE=$BASE"

# Health ya debería estar 200 tras el boot-check
curl -fsS "$BASE/api/health" -o "$OUT/health-$TS.json"
echo "health: $(head -n1 "$OUT/health-$TS.json")"

# OPTIONS CORS
curl -sSI -X OPTIONS "$BASE/api/notes" > "$OUT/options-$TS.txt" || true
echo "-- OPTIONS --"
grep -iE 'HTTP/|access-control|allow' "$OUT/options-$TS.txt" || true

# GET /api/notes (headers + body) - sólo lectura
curl -sSI "$BASE/api/notes?limit=10" > "$OUT/api-notes-headers-$TS.txt" || true
code="$(curl -sS "$BASE/api/notes?limit=10" -o "$OUT/api-notes-$TS.json" -w "%{http_code}" || true)"
echo "-- /api/notes code: $code  len: $(wc -c < "$OUT/api-notes-$TS.json" 2>/dev/null || echo 0)"

# HTML index
curl -fsS "$BASE/?debug=1&nosw=1&v=$RANDOM" -o "$OUT/index-$TS.html" || true
echo "-- index checks --"
grep -q 'class="views"' "$OUT/index-$TS.html" && echo "OK  - .views" || echo "WARN- .views no detectado"
grep -q 'googlesyndication.com/pagead/js/adsbygoogle.js' "$OUT/index-$TS.html" && echo "OK  - AdSense" || echo "WARN- AdSense ausente"
grep -qi 'rel="next"' "$OUT/api-notes-headers-$TS.txt" && echo "OK  - Link: rel=next (encabezado)" || echo "WARN- Link next ausente"

echo "Archivos:"
echo "  $OUT/health-$TS.json"
echo "  $OUT/options-$TS.txt"
echo "  $OUT/api-notes-headers-$TS.txt"
echo "  $OUT/api-notes-$TS.json"
echo "  $OUT/index-$TS.html"
