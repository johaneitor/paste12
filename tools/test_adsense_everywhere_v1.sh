#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://tu-dominio}"
PUB="${2:-ca-pub-9479870293204581}"
OUTDIR="${3:-/sdcard/Download}"

ts(){ date -u +%Y%m%d-%H%M%SZ; }
TS="$(ts)"
mkdir -p "$OUTDIR"

fetch () {
  local path="$1"
  local file="$OUTDIR/index$(echo "$path" | tr '/?' '__')-adsense-$TS.html"
  curl -fsSL -H 'Cache-Control: no-cache' -o "$file" "$BASE$path"
  echo "$file"
}

report="$OUTDIR/adsense-audit-$TS.txt"
: > "$report"
echo "== AdSense everywhere audit =="     | tee -a "$report"
echo "base : $BASE"                        | tee -a "$report"
echo "ts   : $TS"                          | tee -a "$report"
echo                                       | tee -a "$report"

ok=1
for P in "/" "/terms" "/privacy"; do
  FILE="$(fetch "$P")"
  HAS_HEAD=$(grep -c '<head' "$FILE" || true)
  HAS_TAG=$(grep -c 'pagead2\.googlesyndication\.com/pagead/js/adsbygoogle\.js' "$FILE" || true)
  HAS_CID=$(grep -c "client=$PUB" "$FILE" || true)
  printf -- "-- %s --\nHEAD:%s TAG:%s CID:%s\nfile:%s\n\n" "$P" "$HAS_HEAD" "$HAS_TAG" "$HAS_CID" "$FILE" | tee -a "$report"
  if [ "$HAS_TAG" -eq 0 ] || [ "$HAS_CID" -eq 0 ]; then ok=0; fi
done

echo "RESULT: $([ $ok -eq 1 ] && echo OK || echo FAIL)" | tee -a "$report"
echo "Guardado: $report"
