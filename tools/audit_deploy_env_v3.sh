#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
OUT="${HOME}/Download"; mkdir -p "$OUT"
curl -fsSL "$BASE" -D "$OUT/index-h-$TS.txt" -o /dev/null
curl -fsSL "$BASE/terms" -o "$OUT/terms-$TS.html"
curl -fsSL "$BASE/privacy" -o "$OUT/privacy-$TS.html"
curl -fsSL "$BASE/health" -o "$OUT/health-$TS.json" || true
curl -fsSL "$BASE/api/notes?limit=10" -D "$OUT/options-$TS.txt" -o "$OUT/api-notes-$TS.json"
ls -1 "$OUT"/*"$TS"* || true
