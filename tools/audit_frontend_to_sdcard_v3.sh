#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"; OUT="${HOME}/Download"; mkdir -p "$OUT"
curl -fsSI "$BASE" -o "$OUT/index-h-$TS.txt"
curl -fsSL "$BASE" -o "$OUT/index-$TS.html"
curl -fsSL "$BASE/terms" -o "$OUT/terms-$TS.html"
curl -fsSL "$BASE/privacy" -o "$OUT/privacy-$TS.html"
echo "$OUT"
