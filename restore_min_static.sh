#!/usr/bin/env bash
set -Eeuo pipefail
DEST="backend/static"; SRC_CAND=("backend/frontend" "frontend" ".")
mkdir -p "$DEST" "$DEST/css" "$DEST/js" "$DEST/frontend/js"
pick(){ for s in "${SRC_CAND[@]}"; do [ -f "$s/index.html" ] && { echo "$s"; return; }; done; echo ""; }
SRC="$(pick)"; [ -z "$SRC" ] && { echo "❌ No encontré index.html en backend/frontend ni frontend"; exit 1; }
cp -u "$SRC/index.html"                 "$DEST/index.html"           2>/dev/null || true
[ -f "$SRC/css/styles.css" ] && cp -u "$SRC/css/styles.css"         "$DEST/css/styles.css"    || true
[ -f "$SRC/js/app.js" ] && cp -u "$SRC/js/app.js"                   "$DEST/js/app.js"         || true
[ -f "$SRC/frontend/js/app.js" ] && cp -u "$SRC/frontend/js/app.js" "$DEST/frontend/js/app.js"|| true
[ -f "$SRC/ads.txt" ]      && cp -u "$SRC/ads.txt"                  "$DEST/ads.txt"           || true
[ -f "$SRC/privacy.html" ] && cp -u "$SRC/privacy.html"             "$DEST/privacy.html"      || true
[ -f "$SRC/favicon.svg" ]  && cp -u "$SRC/favicon.svg"              "$DEST/favicon.svg"       || true
[ -f "$SRC/favicon.ico" ]  && cp -u "$SRC/favicon.ico"              "$DEST/favicon.ico"       || true
[ -f "$SRC/robots.txt" ]   && cp -u "$SRC/robots.txt"               "$DEST/robots.txt"        || true
echo "✅ backend/static/ listo."
