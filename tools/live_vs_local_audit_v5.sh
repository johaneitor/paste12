#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
OUT="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
mkdir -p "$OUT"

# 01) backend
{
  echo "== 01-backend =="
  echo "BASE: $BASE"
  echo "-- health --"
  curl -sS "$BASE/api/health"
  echo; echo "-- OPTIONS /api/notes --"
  curl -sS -i -X OPTIONS "$BASE/api/notes" | sed -n '1,20p'
} | tee "$OUT/01-backend-$TS.txt" >/dev/null

# 02) preflight
{
  echo "== 02-preflight =="
  curl -sS -i "$BASE/api/notes?limit=10" | sed -n '1,40p'
} | tee "$OUT/02-preflight-$TS.txt" >/dev/null

# 03) api-notes
curl -sS -i "$BASE/api/notes?limit=10" >"$OUT/api-notes-h-$TS.txt" || true
curl -sS "$BASE/api/notes?limit=10" >"$OUT/api-notes-$TS.json" || true
{
  echo "== 03-api-notes =="
  echo "HEADERS:"
  sed -n '1,40p' "$OUT/api-notes-h-$TS.txt" || true
  echo; echo "BODY (len):"
  wc -c "$OUT/api-notes-$TS.json" 2>/dev/null || true
} | tee "$OUT/03-api-notes-$TS.txt" >/dev/null

# 04) frontend (live & local)
curl -sS "$BASE/" >"$OUT/index-live-$TS.html" || true
if [[ -f frontend/index.html ]]; then cp -f frontend/index.html "$OUT/index-local-$TS.html"; fi

sha_live="$(sha256sum "$OUT/index-live-$TS.html" 2>/dev/null | awk '{print $1}')"
sha_loc="$(sha256sum "$OUT/index-local-$TS.html" 2>/dev/null | awk '{print $1}')"

{
  echo "== 04-frontend =="
  echo "sha live: $sha_live"
  echo "sha local: $sha_loc"
  echo "-- HEADERS --"
  curl -sS -i "$BASE/" | sed -n '1,40p'
  echo; echo "-- quick checks (live) --"
  grep -i -c 'google-adsense-account' "$OUT/index-live-$TS.html" 2>/dev/null | xargs -I{} echo "ads meta: {}"
  grep -i -c 'adsbygoogle.js' "$OUT/index-live-$TS.html" 2>/dev/null | xargs -I{} echo "ads script: {}"
  grep -i -c 'class="views"' "$OUT/index-live-$TS.html" 2>/dev/null | xargs -I{} echo "views span: {}"
} | tee "$OUT/04-frontend-$TS.txt" >/dev/null

# 05) resumen
{
  echo "== 05-summary =="
  echo "BASE: $BASE  TS: $TS"
  echo "- health: $(cat "$OUT/01-backend-$TS.txt" | sed -n '3p')"
  echo "- /api/notes HEAD: $(head -n1 "$OUT/api-notes-h-$TS.txt" 2>/dev/null || true)"
  echo "- api-notes body bytes: $(wc -c "$OUT/api-notes-$TS.json" 2>/dev/null | awk '{print $1}')"
  echo "- index live vs local: $( [[ "$sha_live" = "$sha_loc" && -n "$sha_live" ]] && echo 'MATCH' || echo 'DIFF' )"
  echo "Archivos:"
  printf "  %s\n" \
    "$OUT/01-backend-$TS.txt" \
    "$OUT/02-preflight-$TS.txt" \
    "$OUT/03-api-notes-$TS.txt" \
    "$OUT/04-frontend-$TS.txt" \
    "$OUT/05-summary-$TS.txt" \
    "$OUT/index-live-$TS.html" "$OUT/index-local-$TS.html" \
    "$OUT/api-notes-h-$TS.txt" "$OUT/api-notes-$TS.json"
} | tee "$OUT/05-summary-$TS.txt" >/dev/null

echo "OK: auditoría live vs local (5 textos) -> $OUT"
