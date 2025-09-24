#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
OUT="${2:-/sdcard/Download}"
mkdir -p "$OUT"
TS="$(date -u +%Y%m%d-%H%M%SZ)"

set +e
curl -fsS "$BASE/api/health" -o "$OUT/health-$TS.json"
echo "health -> $OUT/health-$TS.json"
curl -fsSI -X OPTIONS "$BASE/api/notes" -o "$OUT/options-$TS.txt"
echo "options -> $OUT/options-$TS.txt"
curl -fsSI "$BASE/api/notes" -o "$OUT/api-notes-h-$TS.txt" || true
code=$?
echo "GET /api/notes headers (exit=$code) -> $OUT/api-notes-h-$TS.txt"
curl -fsS "$BASE/api/notes?limit=10" -o "$OUT/api-notes-$TS.json" || true
echo "body -> $OUT/api-notes-$TS.json (si existe)"

# index + legales + AdSense
curl -fsS "$BASE" -o "$OUT/index-$TS.html" || true
curl -fsSI "$BASE" -o "$OUT/index-headers-$TS.txt" || true
for p in terms privacy; do
  curl -fsS "$BASE/$p" -o "$OUT/$p-$TS.html" || true
  curl -fsSI "$BASE/$p" -o "$OUT/${p}-headers-$TS.txt" || true
done

# resumen
REPORT="$OUT/unified-audit-$TS.txt"
{
  echo "== unified audit =="
  echo "base: $BASE"
  echo "ts  : $TS"
  echo "-- health --"
  [ -f "$OUT/health-$TS.json" ] && head -c 400 "$OUT/health-$TS.json" || echo "(sin archivo)"
  echo; echo
  echo "-- OPTIONS /api/notes --"
  [ -f "$OUT/options-$TS.txt" ] && head -n 50 "$OUT/options-$TS.txt" || echo "(sin archivo)"
  echo; echo
  echo "-- GET /api/notes headers --"
  [ -f "$OUT/api-notes-h-$TS.txt" ] && head -n 50 "$OUT/api-notes-h-$TS.txt" || echo "(sin archivo)"
  echo; echo
  echo "-- GET /api/notes body (primeras 2 líneas) --"
  [ -f "$OUT/api-notes-$TS.json" ] && head -n 2 "$OUT/api-notes-$TS.json" || echo "(sin archivo)"
  echo; echo
  echo "-- index checks (AdSense + .views) --"
  if [ -f "$OUT/index-$TS.html" ]; then
    head -n 200 "$OUT/index-$TS.html" | grep -Eo '<script[^>]+googlesyndication|class="views"' | sort | uniq -c || true
  else
    echo "(sin index)"
  fi
  echo; echo
  echo "-- legales --"
  for p in terms privacy; do
    echo "== $p =="
    [ -f "$OUT/$p-$TS.html" ] && head -n 2 "$OUT/$p-$TS.html" || echo "(sin archivo)"
    [ -f "$OUT/${p}-headers-$TS.txt" ] && head -n 20 "$OUT/${p}-headers-$TS.txt" || true
    echo
  done
  echo "== files =="
  ls -1 "$OUT" | grep "$TS" || true
} > "$REPORT"

echo "Reporte: $REPORT"
