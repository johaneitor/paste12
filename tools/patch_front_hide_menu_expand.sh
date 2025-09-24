#!/usr/bin/env bash
set -euo pipefail

HTML="${1:-frontend/index.html}"
[[ -f "$HTML" ]] || HTML="index.html"
[[ -f "$HTML" ]] || { echo "No encuentro $HTML"; exit 1; }

cp -a "$HTML" "$HTML.bak.$(date +%s)"

if grep -q 'id="shim-hide-menu-expand"' "$HTML"; then
  echo "→ shim hide expand ya presente"
  exit 0
fi

awk '
  /<\/head>/ && !done {
    print "<style id=\"shim-hide-menu-expand\">"
    print ".menu .expand{ display:none !important; }"
    print "</style>"
    done=1
  }
  { print }
' "$HTML" > "$HTML.tmp"

mv "$HTML.tmp" "$HTML"
echo "✓ ocultado .menu .expand en $HTML"
