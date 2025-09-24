#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"
CLIENT_ID="${2:-}"
OUTDIR="${3:-/sdcard/Download}"

if [[ -z "$BASE" || -z "$CLIENT_ID" ]]; then
  echo "Uso: $0 https://tu-app.onrender.com ca-pub-XXXX [/sdcard/Download]"
  exit 2
fi

mkdir -p "$OUTDIR"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
URL="${BASE%/}/?nosw=1&v=$(date +%s)"
HTML="${OUTDIR}/index-adsense-${TS}.html"
REP="${OUTDIR}/adsense-verify-${TS}.txt"
HDR="${OUTDIR}/adsense-headers-${TS}.txt"

echo "[verify-adsense] GET $URL"
curl -fsS -D "$HDR" -o "$HTML" "$URL" || { echo "ERROR: no pude descargar $URL"; exit 3; }

PASS_HEAD=FAIL
PASS_TAG=FAIL
PASS_CLIENT=FAIL

# ¿hay <head> y </head>?
grep -qi "<head" "$HTML" && grep -qi "</head>" "$HTML" && PASS_HEAD=OK

# ¿hay script adsbygoogle?
grep -qi 'pagead2\.googlesyndication\.com/pagead/js/adsbygoogle\.js' "$HTML" && PASS_TAG=OK

# ¿client correcto?
grep -qi "adsbygoogle\.js?client=${CLIENT_ID}" "$HTML" && PASS_CLIENT=OK

{
  echo "== AdSense verify =="
  echo "base : $BASE"
  echo "ts   : $TS"
  echo "file : $HTML"
  echo "HEAD : $PASS_HEAD"
  echo "TAG  : $PASS_TAG"
  echo "CID  : $PASS_CLIENT"
  echo
  echo "-- headers --"
  sed -n '1,40p' "$HDR"
} | tee "$REP"

if [[ "$PASS_HEAD" == OK && "$PASS_TAG" == OK && "$PASS_CLIENT" == OK ]]; then
  echo "[verify-adsense] ✔ Todo OK. Reporte: $REP"
  exit 0
else
  echo "[verify-adsense] ❌ Falta algo (ver $REP)."
  exit 1
fi
