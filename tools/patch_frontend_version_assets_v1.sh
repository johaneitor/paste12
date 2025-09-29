#!/usr/bin/env bash
set -euo pipefail
IDX="$(ls -1 backend/static/index.html static/index.html public/index.html index.html wsgiapp/templates/index.html 2>/dev/null | head -n1)"
[[ -n "$IDX" ]] || { echo "no encontré index.html"; exit 1; }
V="${P12_COMMIT:-$(git rev-parse --short HEAD)}"
tmp="$IDX.tmp.$$"
awk -v v="$V" '
{ line=$0 }
gsub(/(<script[^>]*src=")(\/?[^"?#]*)(\?[^"]*)?(")/, "\\1\\2?v=" v "\\4", line)
gsub(/(<link[^>]*href=")(\/?[^"?#]*)(\?[^"]*)?(")/, "\\1\\2?v=" v "\\4", line)
{ print line }
' "$IDX" > "$tmp" && mv "$tmp" "$IDX"
git add "$IDX"
git commit -m "FE: cache busting de assets v=$V" || true
