#!/usr/bin/env python3
import re, sys, pathlib, shutil

IDX = pathlib.Path("backend/static/index.html")
if not IDX.exists():
    print("✗ backend/static/index.html no existe"); sys.exit(2)

html = IDX.read_text(encoding="utf-8")
bak = IDX.with_suffix(".html.bak")
changed = False

# (1) Eliminar taglines fijos heredados
new = re.sub(r'<div\s+id="tagline"[^>]*>.*?</div>', '', html, flags=re.S|re.I)
if new != html: html, changed = new, True

# (2) Garantizar h2#tagline-rot dentro del header (una sola vez)
if not re.search(r'<h2[^>]*\bid="tagline-rot"\b', html, flags=re.I):
    def _ensure_rot(m):
        block = m.group(0)
        # colocar tras h1.brand si existe, sinó al inicio del header
        if re.search(r'<h1[^>]*\bclass="[^"]*\bbrand\b[^"]*"[^>]*>.*?</h1>', block, flags=re.S|re.I):
            block = re.sub(
                r'(<h1[^>]*\bclass="[^"]*\bbrand\b[^"]*"[^>]*>.*?</h1>)',
                r'\1\n  <h2 id="tagline-rot"></h2>', block, count=1, flags=re.S|re.I
            )
        else:
            block = re.sub(r'(<header\b[^>]*>)', r'\1\n  <h2 id="tagline-rot"></h2>', block, count=1, flags=re.I)
        return block
    new, n = re.subn(r'(<header\b[^>]*>.*?</header>)', _ensure_rot, html, flags=re.S|re.I)
    if n:
        html, changed = new, True

# (3) CSS del brand (idempotente por bloque con id)
css_block = r"""
<style id="brand-colors">
  :root{
    --brand-teal:#14b8a6;    /* teal-500 */
    --brand-orange:#f97316;  /* orange-500 */
  }
  .brand-gradient{
    background: linear-gradient(90deg, var(--brand-teal), var(--brand-orange));
    -webkit-background-clip: text;
    background-clip: text;
    color: transparent;
  }
</style>
""".strip()

if not re.search(r'<style[^>]*\bid="brand-colors"\b', html, flags=re.I):
    # insertar antes de </head>
    new, n = re.subn(r'</head>', css_block + '\n</head>', html, count=1, flags=re.I)
    if n:
        html, changed = new, True

# (4) Añadir clase brand-gradient al h1.brand si falta
def _add_gradient_class(m):
    h1 = m.group(0)
    if re.search(r'class="[^"]*brand-gradient', h1, flags=re.I):
        return h1
    return re.sub(r'class="', 'class="brand-gradient ', h1, count=1, flags=re.I)

new, n = re.subn(r'<h1\b[^>]*class="[^"]*\bbrand\b[^"]*"[^>]*>', _add_gradient_class, html, flags=re.I)
if n: html, changed = new, True

# (5) Guardar si cambió
if not changed:
    print("OK: brand degradado + tagline único ya presentes"); sys.exit(0)

if not bak.exists():
    shutil.copyfile(IDX, bak)
IDX.write_text(html, encoding="utf-8")
print("patched: brand degradado (teal→naranja) + tagline único (backup .bak)")
