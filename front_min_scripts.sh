#!/usr/bin/env bash
set -Eeuo pipefail
f="frontend/index.html"
ts=$(date +%s)

cp -a "$f" "$f.bak.$ts"
# normalizar formato (si existe dos2unix)
dos2unix "$f" 2>/dev/null || true

# Desactivar scripts que suelen duplicar render/listeners
for s in stability_patch views_counter actions_menu share_enhancer hotfix client_fp debug_overlay; do
  sed -i -E "s#<script[^>]+src=[\"']/?js/${s}(\?v=[0-9]+)?\.js[\"'][^>]*></script>#<!-- disabled: /js/${s}.js -->#gI" "$f"
done

# Asegurar que SOLO quede un app.js (con cache-buster nuevo)
sed -i -E "s#<script[^>]+src=[\"']/?js/app\.js(\?v=[0-9]+)?[\"'][^>]*></script>##gI" "$f"
sed -i -E "s#</body>#  <script src=\"/js/app.js?v=${ts}\" defer></script>\n</body>#gI" "$f"

# Asegurar contenedor de feed
if ! grep -q 'id="feed"' "$f"; then
  sed -i -E "s#<main([^>]*)>#<main\1>\n  <div id=\"feed\"></div>#I" "$f"
fi

echo "== <script> tags activos ahora =="
grep -n '<script' "$f" || true

git add "$f"
git commit -m "front: disable extra scripts; leave only app.js; cache-bust v=${ts}" || true
git push -u origin main

echo
echo "✅ Safe-mode aplicado. Tras el redeploy abre:"
echo "   https://paste12-rmsk.onrender.com/?v=${ts}"
