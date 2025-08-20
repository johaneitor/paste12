#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
cd "$(dirname "$0")"

PUB_ID="ca-pub-9479870293204581"
TS=$(date +%s)

# 1) ads.txt en la raíz pública
# Tu app sirve /css y /js desde la raíz, así que colocar ads.txt en frontend/ funciona como /ads.txt
mkdir -p frontend
echo "google.com, pub-9479870293204581, DIRECT, f08c47fec0942fa0" > frontend/ads.txt

# 2) Inyectar Auto Ads en <head> si no existe
if ! grep -q 'pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=' frontend/index.html 2>/dev/null; then
  perl -0777 -pe 's#</head>#  <script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=ca-pub-9479870293204581" crossorigin="anonymous"></script>\n</head>#i' -i frontend/index.html
fi

# 3) (Opcional) punto de inserción "in-feed" (desactivado hasta que tengas SLOT)
#   - Cuando crees un bloque "In-feed" en AdSense, te da un data-ad-slot (número).
#   - Luego reemplazas SLOT_AQUI y descomentas estas líneas si quieres:
# if ! grep -q 'adsbygoogle' frontend/index.html; then
#   perl -0777 -pe 's#<main([^>]*)>#<main$1>\n  <!-- AdSense in-feed (descomenta cuando tengas data-ad-slot) -->\n  <!--\n  <ins class="adsbygoogle" style="display:block" data-ad-format="fluid" data-ad-layout-key="-gw-3+1f-3d+2z" data-ad-client="ca-pub-9479870293204581" data-ad-slot="SLOT_AQUI"></ins>\n  <script>(adsbygoogle=window.adsbygoogle||[]).push({});</script>\n  -->#i' -i frontend/index.html
# fi

# 4) Commit + push
git add frontend/ads.txt frontend/index.html
git commit -m "feat(ads): AdSense Auto Ads + /ads.txt (pub-9479870293204581)" || true
git push -u origin "$(git rev-parse --abbrev-ref HEAD)"

echo "✅ Listo. Tras el redeploy en Render:
- Comprueba https://TU-DOMINIO/ads.txt
- Abre la página y verifica que el <head> tenga el script de AdSense.
- En AdSense: añade tu dominio en 'Sites' y activa Auto Ads.
- Recarga con /?v=$TS para limpiar caché del navegador."
