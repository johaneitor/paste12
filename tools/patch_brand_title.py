#!/usr/bin/env python3
import re, sys, pathlib, shutil
IDX = pathlib.Path("backend/static/index.html")
if not IDX.exists():
    print("ERROR: backend/static/index.html no existe"); sys.exit(2)
orig = IDX.read_text(encoding="utf-8"); bak = IDX.with_suffix(".html.bak")
changed = False; s = orig

# 1) <title>Paste12</title>
if not re.search(r"<title>\s*Paste12\s*</title>", s, flags=re.I):
    if re.search(r"<title>.*?</title>", s, flags=re.S|re.I):
        s = re.sub(r"<title>.*?</title>", "<title>Paste12</title>", s, flags=re.S|re.I, count=1)
    else:
        s = re.sub(r"</head>", "  <title>Paste12</title>\n</head>", s, flags=re.I, count=1)
    changed = True

# 2) <h1 class="brand">Paste12</h1> en el header
if not re.search(r'<h1[^>]*class="[^"]*\bbrand\b[^"]*"[^>]*>\s*Paste12\s*</h1>', s, flags=re.I):
    # si hay h1 dentro del header, lo normalizo
    def fix_h1(m):
        h1 = m.group(0)
        if re.search(r'class="', h1, flags=re.I):
            h1 = re.sub(r'class="([^"]*)"', lambda mm: f'class="{mm.group(1)} brand"', h1, count=1, flags=re.I)
        else:
            h1 = h1.replace("<h1", '<h1 class="brand"')
        h1 = re.sub(r">(.*?)</h1>", ">Paste12</h1>", h1, flags=re.S)
        return h1
    s2, n = re.subn(r"(<header\b[^>]*>.*?)(<h1\b[^>]*>.*?</h1>)(.*?</header>)",
                    lambda mm: mm.group(1)+fix_h1(mm.group(2))+mm.group(3),
                    s, flags=re.S|re.I)
    if n: s, changed = s2, True
    else:
        s2, n = re.subn(r"(<header\b[^>]*>)", r'\1\n  <h1 class="brand">Paste12</h1>', s, flags=re.I)
        if n: s, changed = s2, True
        else:
            s2, n = re.subn(r"(<body\b[^>]*>)", r'\1\n<header><h1 class="brand">Paste12</h1></header>', s, flags=re.I)
            if n: s, changed = s2, True

# 3) tagline bajo el h1
if not re.search(r'<div\s+id="tagline"\b', s, flags=re.I):
    s2, n = re.subn(
        r'(<header\b[^>]*>.*?<h1\b[^>]*class="[^"]*\bbrand\b[^"]*"[^>]*>.*?</h1>)',
        r'\1\n  <div id="tagline">Reta a un amigo · Dime un secreto · Confiesa algo</div>',
        s, flags=re.S|re.I
    )
    if n: s, changed = s2, True

if not changed:
    print("OK: ya estaba con title/brand/tagline"); sys.exit(0)

if not bak.exists():
    shutil.copyfile(IDX, bak)
IDX.write_text(s, encoding="utf-8")
print("patched: title/brand/tagline (backup en backend/static/index.html.bak)")
