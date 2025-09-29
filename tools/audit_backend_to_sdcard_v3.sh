#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"; OUT="${HOME}/Download"; mkdir -p "$OUT"
curl -fsSL "$BASE/health" -o "$OUT/health-$TS.json" || true
curl -fsSI "$BASE/api/notes?limit=10" -o "$OUT/options-$TS.txt"
curl -fsSL "$BASE/api/notes?limit=10" -o "$OUT/api-notes-$TS.json"
curl -fsSL "$BASE/api/deploy-stamp" -o "$OUT/deploy-stamp-$TS.json" || true
echo "$OUT"
