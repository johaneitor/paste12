#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"
CID="${2:-ca-pub-9479870293204581}"
OUTDIR="${3:-/sdcard/Download}"
[[ -n "$BASE" ]] || { echo "Uso: $0 BASE URL [OUTDIR]"; exit 2; }
TS="$(date -u +%Y%m%d-%H%M%SZ)"
REP="$OUTDIR/adsense-legal-audit-$TS.txt"

check(){
  local path="$1" tag="$2"
  local f="$OUTDIR/index_${tag//\//-}-$TS.html"
  local code body
  code="$(curl -sS -o "$f" -w '%{http_code}' "$BASE$path" || true)"
  local headc tagc cidc
  headc="$(grep -ci '<head' "$f" || true)"
  tagc="$(grep -ci 'pagead2.googlesyndication.com/pagead/js/adsbygoogle.js' "$f" || true)"
  cidc="$(grep -ci "$CID" "$f" || true)"
  {
    echo "-- $path -- code:$code HEAD:$headc TAG:$tagc CID:$cidc"
    echo "file:$f"
    echo
  } >> "$REP"
}

echo "base : $BASE" > "$REP"
echo "ts   : $TS"   >> "$REP"
echo >> "$REP"

check "/" "_"
check "/terms" "terms"
check "/privacy" "privacy"

# Resultado global
if grep -q "code:200.*HEAD:[1-9].*TAG:[1-9].*CID:[1-9]" "$REP" \
   && grep -q "-- /terms -- code:200" "$REP" \
   && grep -q "-- /privacy -- code:200" "$REP"; then
  echo "RESULT: OK" >> "$REP"
else
  echo "RESULT: FAIL" >> "$REP"
fi

echo "Guardado: $REP"
