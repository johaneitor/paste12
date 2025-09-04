#!/usr/bin/env python3
import re, sys, pathlib, shutil
IDX = pathlib.Path("backend/static/index.html")
if not IDX.exists():
    print("ERROR: backend/static/index.html no existe"); sys.exit(2)
s = IDX.read_text(encoding="utf-8")
bak = IDX.with_suffix(".html.bak")

# Quitar bloques por marcas
s2 = re.sub(r"<!-- TAGLINE-BEGIN -->.*?<!-- TAGLINE-END -->", "", s, flags=re.S)

# Quitar cualquier id="tagline" residual
s2 = re.sub(r'<div\s+id="tagline"[^>]*>.*?</div>\s*', "", s2, flags=re.S|re.I)

if s2 == s:
    print("OK: no había bloque de tagline/rotador"); sys.exit(0)

if not bak.exists():
    shutil.copyfile(IDX, bak)
IDX.write_text(s2, encoding="utf-8")
print("reverted: tagline rotador eliminado (backup .bak)")
