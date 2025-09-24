#!/usr/bin/env bash
set -euo pipefail

CLIENT="${1:-ca-pub-XXXXXXXXXXXXXXXX}"  # pasa tu client real como 1er arg

find_index() {
  for f in ./frontend/index.html ./static/index.html ./index.html; do
    [[ -f "$f" ]] && { echo "$f"; return; }
  done
  return 1
}

INDEX="$(find_index || true)"
[[ -z "${INDEX:-}" ]] && { echo "❌ No se encontró index.html"; exit 1; }

SNIPPET="<script async src=\"https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=${CLIENT}\" crossorigin=\"anonymous\"></script>"

echo "== Frontend: AdSense en <head> de $INDEX =="

if grep -Fq "pagead2.googlesyndication.com/pagead/js/adsbygoogle.js" "$INDEX"; then
  echo "→ AdSense ya presente (ok)"
else
  sed -i "0,/<\/head>/s|</head>|  ${SNIPPET}\n</head>|" "$INDEX"
  echo "→ Snippet insertado."
fi

echo "Listo."
