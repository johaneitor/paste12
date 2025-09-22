#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: tools/test_adsense_head.sh https://tu-app.onrender.com}"

html="$(curl -fsS "$BASE/")"
bytes=$(printf %s "$html" | wc -c | tr -d ' ')
echo "bytes=$bytes"
if printf %s "$html" | grep -q 'pagead2\.googlesyndication\.com/pagead/js/adsbygoogle\.js'; then
  echo "OK  - AdSense presente en el HTML."
  exit 0
else
  echo "FAIL- no se encontró AdSense en el HTML."
  exit 1
fi
