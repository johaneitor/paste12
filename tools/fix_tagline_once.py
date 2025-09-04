#!/usr/bin/env python3
import re, sys, pathlib, shutil

IDX = pathlib.Path("backend/static/index.html")
if not IDX.exists():
    print("ERROR: backend/static/index.html no existe"); sys.exit(2)

html = IDX.read_text(encoding="utf-8")
bak  = IDX.with_suffix(".html.bak")
changed = False

# Asegurar un solo <div id="tagline"> (si no existe, lo creamos tras el h1.brand)
if re.search(r'<div\s+id="tagline"\b', html, flags=re.I):
    # Normalizar a UNO: dejamos el primero y quitamos el resto
    first_done = False
    def keep_first(m):
        nonlocal first_done
        if first_done:  # borrar duplicados
            return ""
        first_done = True
        return m.group(0)
    new = re.sub(r'<div\s+id="tagline"\b[^>]*>.*?</div>', keep_first, html, flags=re.I|re.S)
    if new != html:
        html, changed = new, True
else:
    # Insertar tras el h1.brand dentro del header; si no hay header/h1, lo metemos al inicio del body
    tag = '<div id="tagline">Reta a un amigo · Dime un secreto · Confiesa algo</div>'
    new, n = re.subn(r'(<header\b[^>]*>.*?<h1[^>]*class="[^"]*\bbrand\b[^"]*"[^>]*>.*?</h1>)',
                     r'\1\n  '+tag, html, flags=re.I|re.S)
    if n == 0:
        new, n = re.subn(r'(<body\b[^>]*>)',
                         r'\1\n<header><h1 class="brand">Paste12</h1>\n  '+tag+r'</header>',
                         html, flags=re.I)
    if n:
        html, changed = new, True

# Inyectar rotador seguro que **reemplaza** texto y evita duplicados
if 'id="tagline-rotator"' not in html:
    rot = r"""
<script id="tagline-rotator">
(() => {
  if (window.__TAGLINE_ROTATOR__) return;  // idempotente
  window.__TAGLINE_ROTATOR__ = true;

  // De-dupe por si algún otro script ya clonó nodos:
  const dups = Array.from(document.querySelectorAll('div#tagline'));
  if (dups.length > 1) dups.slice(1).forEach(n => n.remove());

  let el = document.querySelector('#tagline');
  if (!el) {
    const hdr = document.querySelector('header') || document.body;
    el = document.createElement('div');
    el.id = 'tagline';
    hdr.prepend(el);
  }

  const msgs = [
    'Reta a un amigo',
    'Dime un secreto',
    'Confiesa algo',
    'Manda un reto',
    'Anónimo o no, tú decides'
  ];
  let i = 0;
  el.textContent = msgs[i];
  setInterval(() => {
    i = (i + 1) % msgs.length;
    // Reemplazamos texto (no append):
    el.textContent = msgs[i];
  }, 3000);
})();
</script>"""
    # lo metemos antes de </body>
    html = re.sub(r'</body>', rot + '\n</body>', html, count=1, flags=re.I)
    changed = True

if not changed:
    print("OK: tagline único + rotador ya presentes"); sys.exit(0)

if not bak.exists():
    shutil.copyfile(IDX, bak)
IDX.write_text(html, encoding="utf-8")
print("patched: tagline único + rotador (backup en backend/static/index.html.bak)")
