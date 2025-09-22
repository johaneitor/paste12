#!/usr/bin/env bash
# Uso: tools/test_frontend_injection_v2.sh "https://paste12-rmsk.onrender.com"
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "Falta BASE"; exit 2; }
TMP="$(mktemp)"
curl -fsS "$BASE/?debug=1&nosw=1&v=$(date +%s)" -o "$TMP"

fails=0
grep -q 'pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=' "$TMP" && echo "OK  - AdSense" || { echo "FAIL- AdSense"; fails=$((fails+1)); }
grep -q 'class="views"' "$TMP" && echo "OK  - span.views" || { echo "FAIL- span.views"; fails=$((fails+1)); }

rm -f "$TMP"
if [ "$fails" -eq 0 ]; then
  echo "✔ HTML OK"
  exit 0
else
  echo "✖ HTML incompleto ($fails fallo/s)"
  exit 1
fi
