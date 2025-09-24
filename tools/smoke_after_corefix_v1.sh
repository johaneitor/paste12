#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?BASE requerido}"
OUT="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"

mkdir -p "$OUT"

echo "== Smoke corefix =="
echo "-- health --"
curl -fsS "$BASE/api/health" | tee "$OUT/health-$TS.json"
echo
echo "-- OPTIONS /api/notes --"
curl -fsS -i -X OPTIONS "$BASE/api/notes" | tee "$OUT/options-$TS.txt" >/dev/null
echo "-- GET /api/notes (headers) --"
curl -fsS -i "$BASE/api/notes?limit=10" | tee "$OUT/api-notes-h-$TS.txt" >/dev/null || true
echo "-- GET /api/notes (body) --"
curl -fsS "$BASE/api/notes?limit=10" -o "$OUT/api-notes-$TS.json" || true

# Link header quick check
LINK="$(grep -i '^link:' "$OUT/api-notes-h-$TS.txt" || true)"
if [[ -n "$LINK" ]]; then
  echo "LINK: $LINK"
else
  echo "NO LINK HEADER"
fi

echo "Archivos:"
ls -1 "$OUT"/{health,options,api-notes*}-$TS* 2>/dev/null || true
