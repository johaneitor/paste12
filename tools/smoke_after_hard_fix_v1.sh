#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
OUTDIR="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"

mkdir -p "$OUTDIR"

echo "== Smoke after hard-fix =="
echo "-- health --"
curl -fsS "$BASE/api/health" | tee "$OUTDIR/health-$TS.json"; echo

echo "-- OPTIONS /api/notes --"
curl -fsS -i -X OPTIONS "$BASE/api/notes" | tee "$OUTDIR/options-$TS.txt" >/dev/null

echo "-- GET /api/notes (headers) --"
set +e
curl -sS -I "$BASE/api/notes?limit=10" | tee "$OUTDIR/api-notes-h-$TS.txt"
RC=$?
set -e

LINK=$(grep -i '^link:' "$OUTDIR/api-notes-h-$TS.txt" || true)
echo "-- Link header: ${LINK:-(none)}"

echo "-- Quick FE checks --"
curl -fsS "$BASE/?nosw=1&v=$TS" -o "$OUTDIR/index-$TS.html"
HEADS=$(grep -ic '<meta name="google-adsense-account"' "$OUTDIR/index-$TS.html" || true)
VIEWS=$(grep -ic 'class="views"' "$OUTDIR/index-$TS.html" || true)
echo "AdSense meta tags: $HEADS; span.views: $VIEWS" | tee "$OUTDIR/quick-$TS.txt"

echo
echo "Archivos:"
printf "  %s\n" \
  "$OUTDIR/health-$TS.json" \
  "$OUTDIR/options-$TS.txt" \
  "$OUTDIR/api-notes-h-$TS.txt" \
  "$OUTDIR/index-$TS.html" \
  "$OUTDIR/quick-$TS.txt"

echo "== END =="
