#!/usr/bin/env bash
set -euo pipefail
ADS_ID="${1:-ca-pub-0000000000000000}"
BASE="${2:-https://paste12-rmsk.onrender.com}"
OUT="${3:-/sdcard/Download}"

[[ -d "$OUT" ]] || { echo "ERROR: no existe $OUT (ejecuta termux-setup-storage)"; exit 3; }

TS="$(date -u +%Y%m%d-%H%M%SZ)"

# 0) Reconciliar local
tools/frontend_reconcile_v2.sh frontend/index.html "$ADS_ID" "$BASE"

# 1) BACKEND (health + OPTIONS /api/notes)
F1="$OUT/01-backend-$TS.txt"
{
  echo "==== BACKEND AUDIT ===="
  echo "[base] $BASE"
  echo "[ts]   $TS"
  echo "-- /api/health --"
  curl -sS "$BASE/api/health"
  echo
  echo
  echo "==== OPTIONS /api/notes ===="
  curl -sSi -X OPTIONS "$BASE/api/notes" | sed -n '1,20p'
} > "$F1"
echo "[01] $F1"

# 2) API NOTES (headers + body + Link)
F2="$OUT/02-api-notes-$TS.txt"
B2="$OUT/api-notes-$TS.json"
{
  echo "==== GET /api/notes (headers) ===="
  curl -sSi "$BASE/api/notes?limit=10" | sed -n '1,30p'
  echo
  echo "==== Body (primeras 2 líneas) ===="
  curl -sS "$BASE/api/notes?limit=10" -o "$B2" || true
  head -n 2 "$B2" 2>/dev/null || echo "(sin cuerpo)"
  echo "==== Link header ===="
  grep -i '^link:' "$OUT/02-api-notes-$TS.txt" 2>/dev/null || true
} > "$F2"
echo "[02] $F2"
echo "[02b] $B2"

# 3) FRONTEND (HTML + headers)
F3="$OUT/03-frontend-index-$TS.txt"
H3="$OUT/index-$TS.html"
curl -sS "$BASE/" -o "$H3" || true
{
  echo "==== index headers ===="
  curl -sSi "$BASE/" | sed -n '1,30p'
  echo
  echo "==== checks ===="
  echo "- hotfix v4: $(grep -qi 'hotfix v4' "$H3" && echo OK || echo FAIL)"
  echo "- span.views: $(grep -qi 'class=\"[^\" ]*views' "$H3" && echo OK || echo FAIL)"
  echo "- AdSense meta: $(grep -qi 'name=\"google-adsense-account\"' "$H3" && echo OK || echo FAIL)"
  echo "- AdSense script: $(grep -qi 'googlesyndication.com/pagead/js/adsbygoogle.js' "$H3" && echo OK || echo FAIL)"
} > "$F3"
echo "[03] $F3"
echo "[03h] $H3"

# 4) LEGALES + AdSense en terms/privacy
F4="$OUT/04-adsense-legals-$TS.txt"
T4="$OUT/terms-$TS.html"
P4="$OUT/privacy-$TS.html"
curl -sS "$BASE/terms"   -o "$T4" || true
curl -sS "$BASE/privacy" -o "$P4" || true
{
  echo "==== /terms ===="
  curl -sSi "$BASE/terms"   | sed -n '1,20p'
  echo "HEAD: $(grep -c '<head' "$T4" 2>/dev/null)"
  echo "TAG : $(grep -ci 'googlesyndication.com/pagead/js/adsbygoogle.js' "$T4" 2>/dev/null)"
  echo "CID : $(grep -ci 'google-adsense-account' "$T4" 2>/dev/null)"
  echo
  echo "==== /privacy ===="
  curl -sSi "$BASE/privacy" | sed -n '1,20p'
  echo "HEAD: $(grep -c '<head' "$P4" 2>/dev/null)"
  echo "TAG : $(grep -ci 'googlesyndication.com/pagead/js/adsbygoogle.js' "$P4" 2>/dev/null)"
  echo "CID : $(grep -ci 'google-adsense-account' "$P4" 2>/dev/null)"
} > "$F4"
echo "[04] $F4"

# 5) COMPARE live vs repo (solo hash + checks básicos)
F5="$OUT/05-compare-$TS.txt"
L5="$OUT/index-live-$TS.html"
R5="frontend/index.html"
curl -sS "$BASE/?debug=1&nosw=1&v=$RANDOM" -o "$L5" || true
{
  echo "==== LIVE vs REPO ===="
  printf "sha live: "
  sha1sum "$L5" 2>/dev/null | awk '{print $1}'
  printf "sha repo: "
  sha1sum "$R5" 2>/dev/null | awk '{print $1}'
  echo
  echo "-- checks live --"
  echo "views: $(grep -qi 'class=\"[^\" ]*views' "$L5" && echo OK || echo FAIL)"
  echo "ads  : $(grep -qi 'googlesyndication.com/pagead/js/adsbygoogle.js' "$L5" && echo OK || echo FAIL)"
  echo
  echo "-- checks repo --"
  echo "views: $(grep -qi 'class=\"[^\" ]*views' "$R5" && echo OK || echo FAIL)"
  echo "ads  : $(grep -qi 'google-adsense-account' "$R5" && echo OK || echo FAIL)"
} > "$F5"
echo "[05] $F5"

# 6) RESUMEN
F6="$OUT/06-summary-$TS.txt"
{
  echo "[summary] base=$BASE ts=$TS"
  echo "- 01 backend  : $F1"
  echo "- 02 api notes: $F2 + $B2"
  echo "- 03 frontend : $F3 + $H3"
  echo "- 04 legales  : $F4 (+ $T4, $P4)"
  echo "- 05 compare  : $F5 (+ $L5)"
} > "$F6"
echo "[06] $F6"

echo "== DONE =="
