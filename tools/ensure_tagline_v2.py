#!/usr/bin/env python3
import re, sys, pathlib, shutil
IDX = pathlib.Path("backend/static/index.html")
if not IDX.exists():
    print("ERROR: backend/static/index.html no existe"); sys.exit(2)

s = IDX.read_text(encoding="utf-8")
bak = IDX.with_suffix(".html.bak")

if re.search(r'<div\s+id="tagline"\b', s, flags=re.I):
    print("OK: tagline ya presente"); sys.exit(0)

# insertar tras h1.brand dentro de header
s2, n = re.subn(
    r'(<header\b[^>]*>.*?<h1\b[^>]*class="[^"]*\bbrand\b[^"]*"[^>]*>.*?</h1>)',
    r'\1\n  <div id="tagline">Reta a un amigo · Dime un secreto · Confiesa algo</div>',
    s, flags=re.S|re.I
)
if n == 0:
    # si no hay header/h1.brand, lo ponemos al inicio del body
    s2, n = re.subn(
        r'(<body\b[^>]*>)',
        r'\1\n<header><h1 class="brand">Paste12</h1>\n  <div id="tagline">Reta a un amigo · Dime un secreto · Confiesa algo</div></header>',
        s, flags=re.I
    )
if n == 0:
    print("✗ No pude insertar tagline (no encontré <body> ni <header>/<h1>)"); sys.exit(1)

if not bak.exists():
    shutil.copyfile(IDX, bak)
IDX.write_text(s2, encoding="utf-8")
print("patched: tagline agregado")
