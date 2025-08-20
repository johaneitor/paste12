#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
cd "$(dirname "$0")"

PUB="ca-pub-9479870293204581"
TS=$(date +%s)

# 1) Crear /ads.txt (AdSense lo requiere)
mkdir -p frontend
echo "google.com, pub-9479870293204581, DIRECT, f08c47fec0942fa0" > frontend/ads.txt

# 2) Inyectar el script de Auto Ads en <head> si no existe
if ! grep -q 'pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=' frontend/index.html 2>/dev/null; then
  perl -0777 -pe 's#</head>#  <script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client='"$PUB"'" crossorigin="anonymous"></script>\n</head>#i' -i frontend/index.html
fi

# (Opcional) Ruta explícita para /ads.txt si tu server no sirve ese archivo estático:
# Descomenta si /ads.txt te da 404
#: <<'FIXADS'
#if ! grep -q '@app.get("/ads.txt")' backend/__init__.py; then
#  perl -0777 -pe 's#(def\s+create_app\s*\(\)\s*:[\s\S]*?app\s*=\s*Flask[\s\S]*?app\.static_folder[^\\n]*\\n)#\1\n    @app.get("/ads.txt")\n    def ads_txt():\n        from flask import send_from_directory\n        return send_from_directory(app.static_folder, "ads.txt")\n#\n#    #\n# #i' -i backend/__init__.py
#fi
#FIXADS

# 3) Commit + push (Render redeploy)
git add frontend/ads.txt frontend/index.html backend/__init__.py 2>/dev/null || true
git commit -m "adsense: Auto Ads + /ads.txt (pub-9479870293204581)" || true
git push -u origin "$(git rev-parse --abbrev-ref HEAD)"

echo "✅ Listo. Verifica:
- https://TU-DOMINIO/ads.txt (debe mostrar la línea de ads.txt)
- El <head> tiene el script de AdSense
Luego en AdSense: Sites → agrega tu dominio y activa Auto Ads.
Cache-bust: visita /?v=$TS"
