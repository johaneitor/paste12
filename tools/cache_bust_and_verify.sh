#!/usr/bin/env bash
# Uso: tools/cache_bust_and_verify.sh "https://paste12-rmsk.onrender.com" /sdcard/Download
set -euo pipefail
BASE="${1:-}"; OUT="${2:-/sdcard/Download}"
[ -n "$BASE" ] || { echo "Falta BASE"; exit 2; }
mkdir -p "$OUT"
ts="$(date -u +%s)"
url="$BASE/?debug=1&nosw=1&v=$ts"
file="$OUT/index-nocache-$ts.html"

curl -fsS "$url" -H 'Accept: text/html' -o "$file"

echo "== cache_bust_and_verify =="
echo "URL : $url"
echo "FILE: $file"
grep -q 'id="p12-hotfix-v4"' "$file" && echo "OK  - hotfix v4" || echo "WARN- hotfix v4"
grep -q 'class="views"' "$file"      && echo "OK  - span .views" || echo "FAIL- span .views"
grep -q 'adsbygoogle\.js' "$file"    && echo "OK  - AdSense" || echo "WARN- AdSense ausente"
echo "OK: $file"
