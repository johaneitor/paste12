#!/usr/bin/env python3
import pathlib, re, shutil, sys
IDX = pathlib.Path("backend/static/index.html")
if not IDX.exists():
    print("WARN: backend/static/index.html no existe; nada que hacer"); sys.exit(0)
src = IDX.read_text(encoding="utf-8")
bak = IDX.with_suffix(".html.bak")

# Mantener UNA sola tagline con el texto deseado
wanted = '<div id="tagline">Reta a un amigo · Dime un secreto · Confiesa algo</div>'
# 1) eliminar todas las existentes
src2, _ = re.subn(r'\s*<div\s+id="tagline"[^>]*>.*?</div>\s*', '\n', src, flags=re.I|re.S)
# 2) insertar tras el h1.brand (o al inicio del header)
def inject_once(s):
    pat_h1 = re.compile(r'(<header\b[^>]*>.*?<h1\b[^>]*class="[^"]*\bbrand\b[^"]*"[^>]*>.*?</h1>)', re.I|re.S)
    if pat_h1.search(s):
        return pat_h1.sub(r'\1\n  ' + wanted, s, count=1)
    pat_head = re.compile(r'(<header\b[^>]*>)', re.I)
    if pat_head.search(s):
        return pat_head.sub(r'\1\n  ' + wanted, s, count=1)
    pat_body = re.compile(r'(<body\b[^>]*>)', re.I)
    return pat_body.sub(r'\1\n<header>\n  ' + wanted + '\n</header>', s, count=1)

out = inject_once(src2)
if out == src:
    print("OK: sin cambios en tagline")
    sys.exit(0)
if not bak.exists():
    shutil.copyfile(IDX, bak)
IDX.write_text(out, encoding="utf-8")
print("patched: tagline dedup (backup en .bak)")
