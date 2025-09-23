#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://dominio}"
PUB="${2:-ca-pub-9479870293204581}"
OUTDIR="${3:-/sdcard/Download}"

ts(){ date -u +%Y%m%d-%H%M%SZ; }
TS="$(ts)"; mkdir -p "$OUTDIR"
report="$OUTDIR/adsense-audit-$TS.txt"; : > "$report"

echo "== AdSense everywhere audit ==" | tee -a "$report"
echo "base : $BASE"                   | tee -a "$report"
echo "ts   : $TS"                     | tee -a "$report"; echo | tee -a "$report"

ok=1
for P in / /terms /privacy; do
  file="$OUTDIR/index$(echo "$P" | tr '/?' '__')-adsense-$TS.html"
  code=$(curl -sS -L -o "$file" -w '%{http_code}' "$BASE$P")
  has_tag=0; has_cid=0; has_head=0
  if [[ "$code" == "200" ]]; then
    grep -q '<head' "$file" && has_head=1 || true
    grep -q 'pagead2\.googlesyndication\.com/pagead/js/adsbygoogle\.js' "$file" && has_tag=1 || true
    grep -q "client=$PUB" "$file" && has_cid=1 || true
  else
    ok=0
  fi
  printf -- "-- %s -- code:%s HEAD:%s TAG:%s CID:%s\nfile:%s\n\n" \
    "$P" "$code" "$has_head" "$has_tag" "$has_cid" "$file" | tee -a "$report"
  if [[ "$has_tag" -eq 0 || "$has_cid" -eq 0 ]]; then ok=0; fi
done

echo "RESULT: $([ $ok -eq 1 ] && echo OK || echo FAIL)" | tee -a "$report"
echo "Guardado: $report"
