#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: tools/test_adsense_runtime.sh https://tu-app.onrender.com}"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
echo "== Verificando AdSense en $BASE/"
curl -fsS "$BASE/" -o "$TMP"
bytes=$(wc -c < "$TMP" | tr -d ' ')
echo "bytes=$bytes"
(( bytes > 200 )) && echo "OK  - index > 200 bytes" || { echo "FAIL- index muy pequeño"; exit 1; }
if grep -q 'pagead2.googlesyndication.com/pagead/js/adsbygoogle.js' "$TMP"; then
  echo "OK  - AdSense presente en el HTML servido"
else
  echo "FAIL- no se encontró AdSense en el HTML servido"; exit 1;
fi
echo "✔ Test OK"
