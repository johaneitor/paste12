#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Base URL}"
OUTDIR="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"

mkdir -p "$OUTDIR"

echo "== Smoke & Audit =="
curl -fsS "$BASE/api/health" -o "$OUTDIR/health-$TS.json" || true
echo "health -> $OUTDIR/health-$TS.json"

curl -isS -X OPTIONS "$BASE/api/notes" -o "$OUTDIR/options-$TS.txt" || true
echo "options -> $OUTDIR/options-$TS.txt"

curl -isS "$BASE/api/notes?limit=10" -o "$OUTDIR/api-notes-h-$TS.txt" || true
echo "GET /api/notes headers -> $OUTDIR/api-notes-h-$TS.txt"
if grep -qE "^HTTP/.* 200" "$OUTDIR/api-notes-h-$TS.txt" 2>/dev/null; then
  curl -fsS "$BASE/api/notes?limit=10" -o "$OUTDIR/api-notes-$TS.json" || true
fi

# Frontend
curl -isS "$BASE/"        -o "$OUTDIR/index-h-$TS.txt" || true
curl -fsS "$BASE/"        -o "$OUTDIR/index-$TS.html"  || true
curl -isS "$BASE/terms"   -o "$OUTDIR/terms-h-$TS.txt" || true
curl -fsS "$BASE/terms"   -o "$OUTDIR/terms-$TS.html"  || true
curl -isS "$BASE/privacy" -o "$OUTDIR/privacy-h-$TS.txt" || true
curl -fsS "$BASE/privacy" -o "$OUTDIR/privacy-$TS.html"  || true

# Checks rápidos
echo "-- quick checks --" | tee "$OUTDIR/unified-audit-$TS.txt"
printf "index code: " | tee -a "$OUTDIR/unified-audit-$TS.txt"
grep -m1 -E "^HTTP/" "$OUTDIR/index-h-$TS.txt" | tee -a "$OUTDIR/unified-audit-$TS.txt"

if [[ -f "$OUTDIR/index-$TS.html" ]]; then
  if grep -qi 'name="google-adsense-account"' "$OUTDIR/index-$TS.html"; then
    echo "OK - AdSense meta" | tee -a "$OUTDIR/unified-audit-$TS.txt"
  else
    echo "FAIL - AdSense meta" | tee -a "$OUTDIR/unified-audit-$TS.txt"
  fi
  if grep -q '<span class="views">' "$OUTDIR/index-$TS.html"; then
    echo "OK - span.views" | tee -a "$OUTDIR/unified-audit-$TS.txt"
  else
    echo "FAIL - span.views" | tee -a "$OUTDIR/unified-audit-$TS.txt"
  fi
fi

echo "== Files ==" | tee -a "$OUTDIR/unified-audit-$TS.txt"
ls -1 "$OUTDIR"/*"$TS"* | tee -a "$OUTDIR/unified-audit-$TS.txt"
echo "== END =="
