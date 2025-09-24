#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
OUT="${2:-/sdcard/Download}"
mkdir -p "$OUT"
TS="$(date -u +%Y%m%d-%H%M%SZ)"

echo "== health tester ==" 
echo "base: $BASE"
code_get="$(curl -s -o "$OUT/health-$TS.json" -w "%{http_code}" "$BASE/api/health" || true)"
code_head="$(curl -s -I -o "$OUT/health-head-$TS.txt" -w "%{http_code}" "$BASE/api/health" || true)"

echo "-- GET /api/health -> $code_get"
[[ -s "$OUT/health-$TS.json" ]] && head -n1 "$OUT/health-$TS.json" || true
echo "-- HEAD /api/health -> $code_head"
echo "Archivos:"
echo "  $OUT/health-$TS.json"
echo "  $OUT/health-head-$TS.txt"
