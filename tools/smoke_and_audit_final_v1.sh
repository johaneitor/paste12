#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
OUT="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
mkdir -p "$OUT"

echo "== Smoke FE/BE =="

# health
curl -fsS "$BASE/api/health" -o "$OUT/health-$TS.json" || true

# OPTIONS
curl -isS -X OPTIONS "$BASE/api/notes" -o "$OUT/options-$TS.txt" || true

# GET /api/notes
curl -isS "$BASE/api/notes?limit=10" -o "$OUT/api-notes-h-$TS.txt" || true
curl -fsS "$BASE/api/notes?limit=10" -o "$OUT/api-notes-$TS.json" || true

# GET /
curl -isS "$BASE/" -o "$OUT/index-headers-$TS.txt" || true
curl -fsS "$BASE/" -o "$OUT/index-$TS.html" || true

# checks rápidos
H="$(grep -ic '<meta name=\"google-adsense-account\"' "$OUT/index-$TS.html" || true)"
S="$(grep -ic 'adsbygoogle' "$OUT/index-$TS.html" || true)"
V="$(grep -ic 'class=\"views\"' "$OUT/index-$TS.html" || true)"
T="$(grep -ioc '<h1' "$OUT/index-$TS.html" || true)"

{
  echo "== Resumen ($TS) =="
  echo "health: $(cat "$OUT/health-$TS.json" 2>/dev/null || echo '{}')"
  echo "index: titles=$T ads-meta=$H ads-script=$S views-span=$V"
  echo "archivos:"
  printf "  %s\n" "$OUT/health-$TS.json" "$OUT/options-$TS.txt" "$OUT/api-notes-h-$TS.txt" "$OUT/api-notes-$TS.json" "$OUT/index-headers-$TS.txt" "$OUT/index-$TS.html"
} | tee "$OUT/unified-audit-$TS.txt"

echo "Guardado: $OUT/unified-audit-$TS.txt"
