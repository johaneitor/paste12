#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
cd "$(dirname "$0")"

# ✍️  Puedes exportarlos antes o el script te preguntará:
ADSENSE_CLIENT="${ADSENSE_CLIENT:-}"
AD_SLOT_TOP="${AD_SLOT_TOP:-}"
AD_SLOT_BOTTOM="${AD_SLOT_BOTTOM:-}"
AD_SLOT_INFEED="${AD_SLOT_INFEED:-}"

ask() {
  local var="$1" prompt="$2"
  local cur="${!var}"
  if [ -z "$cur" ]; then
    read -r -p "$prompt: " cur
    eval "$var=\"$cur\""
  fi
}

ask ADSENSE_CLIENT "👉 ID de AdSense (ej. ca-pub-1234567890123456)"
ask AD_SLOT_TOP "👉 Ad slot TOP (ej. 1234567890)"
ask AD_SLOT_BOTTOM "👉 Ad slot BOTTOM (ej. 0987654321)"
ask AD_SLOT_INFEED "👉 Ad slot IN-FEED (ej. 1122334455)"

ts=$(date +%s)
echo "🗂️  Backups .$ts"
for f in frontend/index.html frontend/js/app.js frontend/css/styles.css; do
  [ -f "$f" ] && cp -p "$f" "$f.bak.$ts" || true
done

# 0) Opcional: habilitar Flask-Compress y cache de estáticos
if ! grep -q -i '^Flask-Compress' requirements.txt 2>/dev/null; then
  echo "Flask-Compress~=1.15" >> requirements.txt
fi

python - <<'PY'
import re, pathlib
p = pathlib.Path("backend/__init__.py")
code = p.read_text(encoding="utf-8")
if "from flask_compress import Compress" not in code:
    code = code.replace("from flask_cors import CORS", "from flask_cors import CORS\nfrom flask_compress import Compress")
if "Compress(app)" not in code:
    code = code.replace("CORS(app)", "CORS(app)\n    Compress(app)\n    app.config.setdefault('SEND_FILE_MAX_AGE_DEFAULT', 86400)")
p.write_text(code, encoding="utf-8")
print("✓ backend/__init__.py: Compress + cache estáticos")
PY

# 1) index.html → script AdSense, slots top/bottom, OG/Twitter meta, footer legal
python - <<PY
import os, pathlib, re
client = os.environ["ADSENSE_CLIENT"]
slot_top = os.environ["AD_SLOT_TOP"]
slot_bottom = os.environ["AD_SLOT_BOTTOM"]
p = pathlib.Path("frontend/index.html")
html = p.read_text(encoding="utf-8")

# <head>: AdSense + OG/Twitter si faltan
if "pagead2.googlesyndication.com/pagead/js/adsbygoogle.js" not in html:
  html = html.replace("</head>", f"""
<script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client={client}" crossorigin="anonymous"></script>
<!-- OpenGraph -->
<meta property="og:title" content="Notas rápidas — anónimo y efímero">
<meta property="og:description" content="Publica algo breve y efímero. Likes, vistas y compartir en un clic.">
<meta property="og:image" content="/img/og.png">
<meta property="og:type" content="website">
<!-- Twitter -->
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="Notas rápidas — anónimo y efímero">
<meta name="twitter:description" content="Publica algo breve y efímero. Likes, vistas y compartir en un clic.">
<meta name="twitter:image" content="/img/og.png">
</head>""")

# slot TOP
if '<div id="ad-top"' not in html:
  html = html.replace('<main class="container">', f"""<main class="container">
  <div id="ad-top" class="ad-slot">
    <ins class="adsbygoogle" style="display:block"
         data-ad-client="{client}"
         data-ad-slot="{slot_top}"
         data-ad-format="auto"
         data-full-width-responsive="true"></ins>
    <script>(adsbygoogle=window.adsbygoogle||[]).push({{}});</script>
  </div>
""")

# slot BOTTOM
if '<div id="ad-bottom"' not in html:
  html = html.replace('</main>', f"""
  <div id="ad-bottom" class="ad-slot">
    <ins class="adsbygoogle" style="display:block"
         data-ad-client="{client}"
         data-ad-slot="{slot_bottom}"
         data-ad-format="auto"
         data-full-width-responsive="true"></ins>
    <script>(adsbygoogle=window.adsbygoogle||[]).push({{}});</script>
  </div>
</main>""")

# footer legal con link (si no existe)
if "legal.html" not in html:
  html = html.replace("</body>", """
  <footer class="legal">
    <a href="/legal.html" target="_blank" rel="noopener">Privacidad · Términos</a>
  </footer>
</body>""")

p.write_text(html, encoding="utf-8")
print("✓ index.html: AdSense + OG/Twitter + footer")
PY

# 2) app.js → in-feed ads cada 6 notas (skip en localhost/127.*)
python - <<'PY'
import os, pathlib, re
client = os.environ["ADSENSE_CLIENT"]
slot_infeed = os.environ["AD_SLOT_INFEED"]
p = pathlib.Path("frontend/js/app.js")
js = p.read_text(encoding="utf-8")

if "/* in-feed ads */" not in js:
    js = js.replace(
        "this.list.innerHTML = items.map(n=>`",
        """/* in-feed ads */ 
    const isLocal = ['localhost','127.0.0.1'].some(h=>location.hostname.startsWith(h));
    this.list.innerHTML = items.map(n=>`"""
    )
    js = js.replace(
        ".join(\"\");",
        f""".join("");
    if (!isLocal) {{
      // Inserta slot después de cada 6ª nota
      const lis = Array.from(this.list.querySelectorAll('li.note'));
      lis.forEach((li,i)=>{{
        if ((i+1)%6===0) {{
          const ad = document.createElement('div');
          ad.className = 'ad-slot infeed';
          ad.innerHTML = `
          <ins class="adsbygoogle" style="display:block"
               data-ad-client="{client}"
               data-ad-slot="{slot_infeed}"
               data-ad-format="fluid"
               data-ad-layout-key="-fg+5n+6t-1j-5u"
               data-full-width-responsive="true"></ins>
          <script>(adsbygoogle=window.adsbygoogle||[]).push({{}});</script>`;
          li.after(ad);
        }}
      }});
    }}"""
    )
    p.write_text(js, encoding="utf-8")
    print("✓ app.js: in-feed ads")
else:
    print("• app.js: in-feed ya estaba")
PY

# 3) estilos para slots/footers (idempotente)
if ! grep -q ".ad-slot" frontend/css/styles.css 2>/dev/null; then
cat >> frontend/css/styles.css <<'CSS'

/* anuncios */
.ad-slot{ margin: 14px 0; display:block; }
.ad-slot.infeed{ margin: 10px 0 18px; }
.legal{ text-align:center; font-size:.85rem; opacity:.8; padding:12px 0 18px; }
.legal a{ color: #a0e7ff; text-decoration: none; }
.legal a:hover{ text-decoration: underline; }
CSS
  echo "✓ styles.css: clases para anuncios y footer"
else
  echo "• styles.css: ya tenía estilos de anuncios"
fi

# 4) ads.txt + robots.txt + imagen OG placeholder
mkdir -p frontend/img
# ads.txt (Google requiere DIRECT + ID)
cat > frontend/ads.txt <<TXT
google.com, ${ADSENSE_CLIENT/ca-pub-/}, DIRECT, f08c47fec0942fa0
TXT
echo "✓ frontend/ads.txt"

# robots.txt (básico)
cat > frontend/robots.txt <<'TXT'
User-agent: *
Allow: /
TXT
echo "✓ frontend/robots.txt"

# og.png (placeholder 1200x630 sólido turquesa) — generado con Python (sin Pillow)
python - <<'PY'
import zlib, struct, os
w,h=1200,630
rgba = b'\x30\xcc\xcc\xff'  # turquesa con alpha 255
row = b'\x00' + rgba*w      # 1 filtro + píxeles
raw = row*h
import io
buf=io.BytesIO()
def png_chunk(tag, data):
    return struct.pack("!I", len(data)) + tag + data + struct.pack("!I", zlib.crc32(tag+data)&0xffffffff)
buf.write(b"\x89PNG\r\n\x1a\n")
buf.write(png_chunk(b'IHDR', struct.pack("!IIBBBBB", w, h, 8, 6, 0, 0, 0)))
buf.write(png_chunk(b'IDAT', zlib.compress(raw, 9)))
buf.write(png_chunk(b'IEND', b''))
open("frontend/img/og.png","wb").write(buf.getvalue())
print("✓ frontend/img/og.png generado")
PY

# 5) Instalar dependencias nuevas y reiniciar local (scheduler off)
source venv/bin/activate
pip install -q -r requirements.txt || true

pkill -f "python run.py" 2>/dev/null || true
pkill -f waitress 2>/dev/null || true
: > .paste12.log
nohup env PYTHONUNBUFFERED=1 DISABLE_SCHEDULER=1 python run.py >> .paste12.log 2>&1 &
echo "🟢 PID $!"
sleep 1
tail -n 30 .paste12.log

echo
echo "✅ Hecho. Verifica en producción:"
echo "   • /ads.txt"
echo "   • OpenGraph (pega una URL de nota en X/WhatsApp para ver la preview)"
echo "   • Anuncios: recuerda que en localhost no se muestran."
