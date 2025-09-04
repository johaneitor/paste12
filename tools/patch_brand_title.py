#!/usr/bin/env python3
import re, sys, pathlib, shutil

IDX = pathlib.Path("backend/static/index.html")
if not IDX.exists():
    print("ERROR: backend/static/index.html no existe"); sys.exit(2)

orig = IDX.read_text(encoding="utf-8")
bak = IDX.with_suffix(".html.bak")

changed = False
s = orig

# --- <title>Paste12</title> ---
if re.search(r"<title>\s*Paste12\s*</title>", s, flags=re.I):
    pass
else:
    if re.search(r"<title>.*?</title>", s, flags=re.S|re.I):
        s = re.sub(r"<title>.*?</title>", "<title>Paste12</title>", s, flags=re.S|re.I, count=1)
    else:
        s = re.sub(r"</head>", "  <title>Paste12</title>\n</head>", s, flags=re.I, count=1)
    changed = True

# --- <h1 class="brand">Paste12</h1> en <header> ---
def ensure_brand_h1(html: str):
    # Si ya hay h1.brand con Paste12, nada
    if re.search(r'<h1[^>]*class="[^"]*\bbrand\b[^"]*"[^>]*>\s*Paste12\s*</h1>', html, flags=re.I):
        return html, False
    # Si hay un <header> con un <h1> cualquiera => sustituyo su contenido a Paste12 y agrego class brand
    def _fix_h1(m):
        h1 = m.group(0)
        # fuerza class brand (sin romper otras clases)
        if re.search(r'class="', h1, flags=re.I):
            h1 = re.sub(r'class="([^"]*)"', lambda mm: f'class="{mm.group(1)} brand"', h1, count=1, flags=re.I)
        else:
            h1 = h1.replace("<h1", '<h1 class="brand"')
        # fuerza el texto
        h1 = re.sub(r">(.*?)</h1>", ">Paste12</h1>", h1, flags=re.S)
        return h1
    # header con h1
    new_html, n = re.subn(r"(<header\b[^>]*>.*?)(<h1\b[^>]*>.*?</h1>)(.*?</header>)",
                          lambda mm: mm.group(1) + _fix_h1(mm.group(2)) + mm.group(3),
                          html, flags=re.S|re.I)
    if n:
        return new_html, True
    # Si no hay h1 en header, intento inyectarlo al inicio del header
    new_html, n = re.subn(r"(<header\b[^>]*>)", r'\1\n  <h1 class="brand">Paste12</h1>', html, flags=re.I)
    if n:
        return new_html, True
    # Si no hay header, inserto al inicio del body
    new_html, n = re.subn(r"(<body\b[^>]*>)", r'\1\n<header><h1 class="brand">Paste12</h1></header>', html, flags=re.I)
    return (new_html, True) if n else (html, False)

s2, ch = ensure_brand_h1(s)
s = s2; changed = changed or ch

# --- <div id="tagline">…</div> debajo del h1 dentro de header ---
if re.search(r'<div\s+id="tagline"\b', s, flags=re.I):
    pass
else:
    # insertar tras h1.brand dentro del header
    s2, n = re.subn(
        r'(<header\b[^>]*>.*?<h1\b[^>]*class="[^"]*\bbrand\b[^"]*"[^>]*>.*?</h1>)',
        r'\1\n  <div id="tagline">Reta a un amigo · Dime un secreto · Confiesa algo</div>',
        s, flags=re.S|re.I
    )
    if n:
        s = s2; changed = True

if not changed:
    print("OK: ya estaba con title/brand/tagline")
    sys.exit(0)

# backup y escribir
if not bak.exists():
    shutil.copyfile(IDX, bak)
IDX.write_text(s, encoding="utf-8")
print("patched: title/brand/tagline (backup en backend/static/index.html.bak)")
