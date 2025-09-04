#!/usr/bin/env python3
import re, sys, pathlib, shutil
IDX = pathlib.Path("backend/static/index.html")
if not IDX.exists():
    print("ERROR: backend/static/index.html no existe"); sys.exit(2)

html = IDX.read_text(encoding="utf-8")
if re.search(r'<div\s+id="tagline"\b', html, re.I):
    print("OK: tagline ya presente"); sys.exit(0)

tag = '<div id="tagline">Reta a un amigo · Dime un secreto · Confiesa algo</div>'
# 1) después de h1.brand (más flexible)
pat_h1 = re.compile(r'(<h1[^>]*class="[^"]*\bbrand\b[^"]*"[^>]*>\s*Paste12\s*</h1>)', re.I)
new, n = pat_h1.subn(r'\1\n  '+tag, html, count=1)
if n == 0:
    # 2) no hay h1.brand -> insertar ambos en body
    new, n = re.subn(r'(<body\b[^>]*>)',
                     r'\1\n<header><h1 class="brand">Paste12</h1>\n  '+tag+r'</header>',
                     html, flags=re.I, count=1)
if n == 0:
    print("✗ No pude insertar tagline"); sys.exit(1)

bak = IDX.with_suffix(".html.bak")
if not bak.exists():
    shutil.copyfile(IDX, bak)
IDX.write_text(new, encoding="utf-8")
print("patched: tagline añadido")
