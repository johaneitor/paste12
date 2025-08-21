#!/usr/bin/env bash
set -Eeuo pipefail
ts=$(date +%s)
f="frontend/index.html"

cp -a "$f" "$f.bak.$ts"

disable() {
  local name="$1"
  sed -i -E "s#<script[^>]*src=\"/js/${name}(\?v=[0-9]+)?\.js\"[^>]*></script>#<!-- disabled: /js/${name}.js -->#g" "$f"
}

# Desactivar scripts que suelen reinyectar contenido o duplicar listeners
for s in stability_patch views_counter actions_menu share_enhancer hotfix client_fp; do
  disable "$s"
done

# Asegurar un único app.js con cache-buster nuevo
if grep -qE '<script[^>]*src="/js/app\.js' "$f"; then
  sed -i -E "s#<script[^>]*src=\"/js/app\.js(\?v=[0-9]+)?\"[^>]*></script>#<script src=\"/js/app.js?v=$ts\"></script>#g" "$f"
else
  sed -i "s#</body>#  <script src=\"/js/app.js?v=$ts\"></script>\n</body>#g" "$f"
fi

# Contenedor del feed (si falta)
if ! grep -q 'id="feed"' "$f"; then
  if grep -q '<main' "$f"; then
    sed -i "s#<main[^>]*>#&\n  <div id=\"feed\"></div>#g" "$f"
  else
    sed -i "s#</body>#  <div id=\"feed\"></div>\n</body>#g" "$f"
  fi
fi

echo "— Script tags activos ahora:"
grep -n '<script' "$f" || true

git add "$f"
git commit -m "front(safe-mode): solo app.js; deshabilitar scripts extra; añadir #feed; cache-buster" || true
git push -u origin main
echo "✓ Safe-mode aplicado. Abrí /?v=$ts después del redeploy."
