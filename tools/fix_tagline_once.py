#!/usr/bin/env python3
import re, sys, pathlib, shutil

IDX = pathlib.Path("backend/static/index.html")
if not IDX.exists():
    print("✗ backend/static/index.html no existe"); sys.exit(2)
html = IDX.read_text(encoding="utf-8")
bak  = IDX.with_suffix(".html.bak")
changed = False

# 1) eliminar duplicados de <div id="tagline">…</div>
html_new = re.sub(r'(<div\s+id="tagline"[^>]*>.*?</div>)', r'\1', html, flags=re.S|re.I)
# quito repetidos dejando sólo el primero
parts = re.split(r'(<div\s+id="tagline"[^>]*>.*?</div>)', html_new, flags=re.S|re.I)
seen = False
out = []
for p in parts:
    if re.match(r'<div\s+id="tagline"[^>]*>.*?</div>', p, flags=re.S|re.I):
        if not seen:
            out.append(p); seen = True
        else:
            changed = True  # drop duplicado
    else:
        out.append(p)
html = "".join(out)

# 2) asegurar UNA SOLA tagline bajo el h1.brand dentro de <header>
has_tag = re.search(r'<div\s+id="tagline"\b', html, flags=re.I)
if not has_tag:
    # insertar justo después de h1.brand
    pat = re.compile(r'(<header\b[^>]*>.*?<h1\b[^>]*class="[^"]*\bbrand\b[^"]*"[^>]*>.*?</h1>)', flags=re.S|re.I)
    repl = r'\1\n  <div id="tagline">Reta a un amigo · Dime un secreto · Confiesa algo</div>'
    html2, n = pat.subn(repl, html, count=1)
    if n == 0:
        # fallback: al inicio de <body>
        html2, n = re.subn(r'(<body\b[^>]*>)', r'\1\n<header><h1 class="brand">Paste12</h1>\n  <div id="tagline">Reta a un amigo · Dime un secreto · Confiesa algo</div></header>', html, count=1, flags=re.I)
    if n:
        html = html2; changed = True

if not changed:
    print("OK: tagline única y posicionada")
    sys.exit(0)

if not bak.exists():
    shutil.copyfile(IDX, bak)
IDX.write_text(html, encoding="utf-8")
print("patched: tagline única (backup .bak)")
