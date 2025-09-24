#!/usr/bin/env bash
set -euo pipefail

BASE="${1:-https://paste12-rmsk.onrender.com}"
OUTDIR="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
REPORT="$OUTDIR/unified-audit-$TS.txt"

mkdir -p "$OUTDIR" || { echo "ERROR: no puedo escribir en $OUTDIR (ejecuta: termux-setup-storage)"; exit 1; }

echo "== Unified audit =="            | tee "$REPORT"
echo "base: $BASE"                   | tee -a "$REPORT"
echo "ts  : $TS"                     | tee -a "$REPORT"

# Health
curl -fsS "$BASE/api/health" -o "$OUTDIR/health-$TS.json" || true
echo "-- health --"                  | tee -a "$REPORT"
echo "file: $OUTDIR/health-$TS.json" | tee -a "$REPORT"
jq -c . < "$OUTDIR/health-$TS.json" 2>/dev/null | tee -a "$REPORT" || echo "(sin JSON legible)" | tee -a "$REPORT"

# OPTIONS
echo "-- OPTIONS /api/notes --"      | tee -a "$REPORT"
curl -fsS -i -X OPTIONS "$BASE/api/notes" | sed -n '1,20p' | tee -a "$REPORT"

# GET /api/notes (headers + body corto)
echo "-- GET /api/notes headers --"  | tee -a "$REPORT"
curl -fsS -D - "$BASE/api/notes?limit=10" -o /dev/null | sed -n '1,40p' | tee -a "$REPORT"
echo "-- GET /api/notes body (first line) --" | tee -a "$REPORT"
curl -fsS "$BASE/api/notes?limit=10" -o "$OUTDIR/api-notes-$TS.json" || true
head -c 200 "$OUTDIR/api-notes-$TS.json" | sed 's/[^[:print:]\t]/?/g' | tee -a "$REPORT"; echo | tee -a "$REPORT"

# Link header (presencia)
echo "-- Link header check --"       | tee -a "$REPORT"
curl -fsS -D - "$BASE/api/notes?limit=10" -o /dev/null | awk 'BEGIN{f=0}/^Link:/{f=1}f{print}' | tee -a "$REPORT"

# AdSense (/, /terms, /privacy)
check_ads () {
  local path="$1"
  local name="${2:-root}"
  local file="$OUTDIR/index_${name}-ads-$TS.html"
  curl -fsS "$BASE$path" -o "$file" || { echo "$path code:ERR" | tee -a "$REPORT"; return; }
  local code; code="$(curl -s -o /dev/null -w "%{http_code}" "$BASE$path")"
  local HEAD=$(grep -ci "<head" "$file" || true)
  local TAG=$(grep -ci "pagead2\.googlesyndication\.com" "$file" || true)
  local CID=$(grep -ci "client=ca-pub-9479870293204581" "$file" || true)
  echo "-- $path -- code:$code HEAD:$HEAD TAG:$TAG CID:$CID" | tee -a "$REPORT"
}
echo "-- AdSense check --" | tee -a "$REPORT"
check_ads "/" "-"
check_ads "/terms" "terms"
check_ads "/privacy" "privacy"

echo "== Files =="                    | tee -a "$REPORT"
echo "  $OUTDIR/health-$TS.json"      | tee -a "$REPORT"
echo "  $OUTDIR/api-notes-$TS.json"   | tee -a "$REPORT"
echo "  $OUTDIR/index_-ads-$TS.html"  | tee -a "$REPORT"
echo "  $OUTDIR/index_terms-ads-$TS.html" | tee -a "$REPORT"
echo "  $OUTDIR/index_privacy-ads-$TS.html" | tee -a "$REPORT"
echo "== END =="                      | tee -a "$REPORT"
echo "Guardado: $REPORT"
