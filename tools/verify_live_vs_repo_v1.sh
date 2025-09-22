#!/usr/bin/env bash
# Uso: tools/verify_live_vs_repo_v1.sh "https://paste12-rmsk.onrender.com" /sdcard/Download
set -euo pipefail
BASE="${1:-}"; OUT="${2:-/sdcard/Download}"
[ -n "$BASE" ] || { echo "Falta BASE"; exit 2; }
mkdir -p "$OUT" .tmp

ts="$(date -u +%Y%m%d-%H%M%SZ)"
live="$OUT/index-live-$ts.html"
loc="$OUT/index-local-$ts.html"
rep="$OUT/frontend-compare-$ts.txt"

curl -fsS "$BASE" -H 'Accept: text/html' -o "$live"
[ -f frontend/index.html ] && cp -f frontend/index.html "$loc" || echo "(no existe frontend/index.html local)" > "$loc"

h_live="$(sha256sum "$live" | awk '{print $1}')"
h_loc="$(sha256sum "$loc"  | awk '{print $1}')"

chk(){
  local name="$1" rx="$2" file="$3"
  if grep -qE "$rx" "$file"; then echo "OK  - $name"; else echo "FAIL- $name"; fi
}

{
  echo "== verify_live_vs_repo_v1 =="
  echo "BASE: $BASE"
  echo "ts  : $ts"
  echo "live: $live"
  echo "loc : $loc"
  echo "sha live: $h_live"
  echo "sha loc : $h_loc"
  if [ "$h_live" = "$h_loc" ]; then echo "OK  - HTML remoto coincide con repo"; else echo "WARN- HTML remoto distinto al repo"; fi
  echo ""
  echo "-- checks en remoto --"
  chk "views span (.views)"            'class="views"|<span[^>]+class="views' "$live"
  chk "hotfix v4 presente"             'id="p12-hotfix-v4"'                  "$live"
  chk "summary-enhancer presente"      'id="summary-enhancer"'               "$live"
  chk "Link/next (paginacion) hint"    'rel="?next"?|X-Next-Cursor'          "$live"
  chk "AdSense presente"               'googlesyndication\.com/pagead/js/adsbygoogle\.js' "$live"
  echo ""
  echo "-- checks en local --"
  chk "views span (.views)"            'class="views"|<span[^>]+class="views' "$loc"
  chk "AdSense presente"               'googlesyndication\.com/pagead/js/adsbygoogle\.js' "$loc"
} | tee "$rep"

echo "OK: reporte $rep"
echo "OK: $live"
echo "OK: $loc"
