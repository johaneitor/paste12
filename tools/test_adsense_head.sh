#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: tools/test_adsense_head.sh https://tu-app.onrender.com}"

echo "== Verificando AdSense en $BASE =="
TMP="$(mktemp)"
curl -fsS "$BASE/" -o "$TMP"
bytes=$(wc -c < "$TMP" | tr -d ' ')
echo "bytes=$bytes"
(( bytes > 200 )) && echo "OK  - index > 200 bytes" || { echo "FAIL- index muy pequeño"; exit 1; }

if grep -q 'googlesyndication.com/pagead/js/adsbygoogle.js' "$TMP"; then
  echo "OK  - AdSense detectado en el HTML servido"
else
  echo "FAIL- no se encontró AdSense en el HTML servido"; exit 1;
fi
rm -f "$TMP"
echo "✔ Test OK"
