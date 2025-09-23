#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
OUT="${2:-/sdcard/Download}"
mkdir -p "$OUT"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
FN="$OUT/unified-audit-${TS}.txt"

hcurl(){ curl -fsS -m 20 -D - -o /dev/null "$1" || true; }

echo "== Unified audit (super) =="          | tee "$FN"
echo "base: $BASE"                          | tee -a "$FN"
echo "ts  : $TS"                            | tee -a "$FN"

# Health
curl -fsS "$BASE/api/health" -o "$OUT/health-$TS.json" || true
echo "-- health --"                         | tee -a "$FN"
[[ -s "$OUT/health-$TS.json" ]] && cat "$OUT/health-$TS.json" | tee -a "$FN"

# CORS/OPTIONS
echo "-- OPTIONS /api/notes --"             | tee -a "$FN"
curl -fsS -X OPTIONS -D - -o /dev/null "$BASE/api/notes" | sed -n '1,20p' | tee -a "$FN" || true

# GET headers (no HEAD)
echo "-- GET /api/notes headers --"         | tee -a "$FN"
curl -fsS -D - -o "$OUT/api-notes-$TS.json" "$BASE/api/notes?limit=10" | sed -n '1,20p' | tee -a "$FN" || true
echo "-- GET /api/notes body (first line) --" | tee -a "$FN"
head -n1 "$OUT/api-notes-$TS.json" | tee -a "$FN" || true

# Link header
echo "-- Link header check --"              | tee -a "$FN"
grep -i '^link:' -m1 "$OUT/api-notes-$TS.json" >/dev/null 2>&1 || true
hcurl "$BASE/api/notes?limit=10" | awk 'BEGIN{f=0} /^Link:/ {print; f=1} END{if(f==0) print "NO LINK HEADER"}' | tee -a "$FN"

# AdSense y legal en 3 rutas
check_ads(){
  local path="$1" tag_head tag_src cid
  curl -fsS "$BASE$path" -o "$OUT/index_${path//\//-}-ads-$TS.html" || true
  tag_head=$(grep -c -i '<script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js' "$OUT/index_${path//\//-}-ads-$TS.html" || true)
  tag_src=$(grep -c -i 'googlesyndication' "$OUT/index_${path//\//-}-ads-$TS.html" || true)
  cid=$(grep -c 'client=ca-pub-' "$OUT/index_${path//\//-}-ads-$TS.html" || true)
  echo "-- $path -- code:$(
    curl -s -o /dev/null -w "%{http_code}" "$BASE$path"
  ) HEAD:$tag_head TAG:$tag_src CID:$cid" | tee -a "$FN"
}
echo "-- AdSense check --"                  | tee -a "$FN"
check_ads "/"
check_ads "/terms"
check_ads "/privacy"

echo "== Files =="                          | tee -a "$FN"
echo "  $OUT/health-$TS.json"               | tee -a "$FN"
echo "  $OUT/api-notes-$TS.json"            | tee -a "$FN"
echo "  $OUT/index_--ads-$TS.html"          | tee -a "$FN"
echo "  $OUT/index_terms-ads-$TS.html"      | tee -a "$FN"
echo "  $OUT/index_privacy-ads-$TS.html"    | tee -a "$FN"
echo "== END =="                            | tee -a "$FN"
echo "Guardado: $FN"
