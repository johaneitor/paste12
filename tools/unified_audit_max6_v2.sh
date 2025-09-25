#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; OUT="${2:-/sdcard/Download}"
[[ -n "$BASE" ]] || { echo "USO: $0 BASE_URL [/sdcard/Download]"; exit 2; }
mkdir -p "$OUT"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
MAIN="$OUT/unified-audit-$TS.txt"

HEALTH="$OUT/health-$TS.json"
OPTH="$OUT/options-$TS.txt"
HNOT="$OUT/api-notes-h-$TS.txt"
BNOT="$OUT/api-notes-$TS.json"
IDXH="$OUT/index-$TS.html"

{
echo "== Unified audit =="
echo "base: $BASE"
echo "ts  : $TS"
echo
echo "-- health --"
curl -sS "$BASE/api/health" | tee "$HEALTH"

echo
echo "-- OPTIONS /api/notes --"
curl -sSi -X OPTIONS "$BASE/api/notes" | sed -n '1,20p' | tee "$OPTH" >/dev/null

echo
echo "-- GET /api/notes headers --"
code="$(curl -sS -w '%{http_code}' -D "$HNOT" -o "$BNOT" "$BASE/api/notes?limit=10")"
head -n 20 "$HNOT"
if [ "$code" = "200" ]; then
  echo
  echo "-- GET /api/notes body (len) --"
  wc -c "$BNOT"
else
  echo
  echo "WARN: GET /api/notes code=$code (no se guarda body si !=200)"
  rm -f "$BNOT" || true
fi

echo
echo "-- index checks --"
curl -sS "$BASE/" -o "$IDXH"
if [ -f "$IDXH" ]; then
  ctitle="$(grep -c -i '<title' "$IDXH" || true)"
  cviews="$(grep -c 'class=\"views\"' "$IDXH" || true)"
  cmeta="$(grep -c 'google-adsense-account' "$IDXH" || true)"
  ctag="$(grep -c 'pagead2.googlesyndication.com/pagead/js/adsbygoogle.js' "$IDXH" || true)"
  echo "titles: $ctitle  views-span: $cviews  ads-meta: $cmeta  ads-script: $ctag"
else
  echo "ERROR: no pude bajar /"
fi

echo
echo "== files =="
echo "  $HEALTH"
echo "  $OPTH"
echo "  $HNOT"
[ -f "$BNOT" ] && echo "  $BNOT"
echo "  $IDXH"
} | tee "$MAIN"

echo "Guardado: $MAIN"
