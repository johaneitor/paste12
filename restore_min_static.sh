#!/usr/bin/env bash
set -Eeuo pipefail
DEST="backend/static"; SRC_CAND=("backend/frontend" "frontend")
mkdir -p "$DEST" "$DEST/css" "$DEST/js" "$DEST/frontend/js"
pick(){ for s in "${SRC_CAND[@]}"; do [ -f "$s/index.html" ] && { echo "$s"; return; }; done; echo ""; }
SRC="$(pick)"; [ -z "$SRC" ] && { echo "No encontré index.html en backend/frontend ni frontend"; exit 1; }
cp -u "$SRC/index.html"                 "$DEST/index.html"        2>/dev/null || true
cp -u "$SRC/css/styles.css"             "$DEST/css/styles.css"    2>/dev/null || true
cp -u "$SRC/js/app.js"                  "$DEST/js/app.js"         2>/dev/null || true
cp -u "$SRC/frontend/js/app.js"         "$DEST/frontend/js/app.js" 2>/dev/null || true
cp -u "$SRC/ads.txt"                    "$DEST/ads.txt"           2>/dev/null || true
cp -u "$SRC/favicon.svg"                "$DEST/favicon.svg"       2>/dev/null || true
cp -u "$SRC/favicon.ico"                "$DEST/favicon.ico"       2>/dev/null || true
cp -u "$SRC/robots.txt"                 "$DEST/robots.txt"        2>/dev/null || true
echo "✅ backend/static/ rellenado."
