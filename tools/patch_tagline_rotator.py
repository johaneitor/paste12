#!/usr/bin/env python3
import re, sys, pathlib, shutil

IDX = pathlib.Path("backend/static/index.html")
if not IDX.exists():
    print("ERROR: backend/static/index.html no existe"); sys.exit(2)

html = IDX.read_text(encoding="utf-8")
bak  = IDX.with_suffix(".html.bak")

TAG_BEGIN = "<!-- TAGLINE-BEGIN -->"
TAG_END   = "<!-- TAGLINE-END -->"
STYLE_ID  = 'tagline-style'
SCRIPT_ID = 'tagline-rotator-js'
PHRASES   = "Reta a un amigo|Dime un secreto|Confiesa algo|Manda un reto|Anónimo o no, tú decides"
FALLBACK  = "Reta a un amigo · Dime un secreto · Confiesa algo"

changed = False

# 0) Remover bloque anterior por marcas (idempotente)
html2 = re.sub(r"<!-- TAGLINE-BEGIN -->.*?<!-- TAGLINE-END -->", "", html, flags=re.S)
if html2 != html:
    html = html2
    changed = True

# 1) Eliminar CUALQUIER duplicado de id="tagline" viejo
html2 = re.sub(r'<div\s+id="tagline"[^>]*>.*?</div>\s*', "", html, flags=re.S|re.I)
if html2 != html:
    html = html2
    changed = True

# 2) Asegurar <style id="tagline-style"> UNA sola vez en <head>
style_block = (
    f'<!-- TAGLINE-BEGIN -->\n'
    f'<style id="{STYLE_ID}">\n'
    f'  #tagline{{margin:.25rem 0 0;opacity:.9;line-height:1.25;}}\n'
    f'  #tagline .tg-text{{font-weight:500;}}\n'
    f'</style>\n'
    f'<!-- TAGLINE-END -->\n'
)
if f'id="{STYLE_ID}"' not in html:
    # Inserta antes de </head>. Si no hay, lo mete al inicio del body como fallback.
    if re.search(r"</head>", html, flags=re.I):
        html = re.sub(r"</head>", style_block + "</head>", html, count=1, flags=re.I)
    else:
        html = re.sub(r"<body(\b[^>]*)>", r"<body\1>\n" + style_block, html, count=1, flags=re.I)
    changed = True

# 3) Construir bloque de tagline + rotador con GUARD global
tagline_block = (
    f'<!-- TAGLINE-BEGIN -->\n'
    f'<div id="tagline" class="tagline" data-phrases="{PHRASES}">\n'
    f'  <div class="tg-text">{FALLBACK}</div>\n'
    f'</div>\n'
    f'<script id="{SCRIPT_ID}">\n'
    f'(function(){{\n'
    f'  if (window.__taglineRotatorInstalled) return; window.__taglineRotatorInstalled = 1;\n'
    f'  try {{\n'
    f'    var el = document.getElementById("tagline"); if(!el) return;\n'
    f'    var tgt = el.querySelector(".tg-text") || el;\n'
    f'    var raw = el.getAttribute("data-phrases") || "";\n'
    f'    var parts = raw.split("|").map(function(s){{return s.trim();}}).filter(Boolean);\n'
    f'    if (!parts.length) return;\n'
    f'    var i = 0; tgt.textContent = parts[0];\n'
    f'    setInterval(function(){{ i=(i+1)%parts.length; tgt.textContent = parts[i]; }}, 3000);\n'
    f'  }} catch(e){{ /* silencioso */ }}\n'
    f'}})();\n'
    f'</script>\n'
    f'<!-- TAGLINE-END -->\n'
)

def insert_after_brand(s: str) -> tuple[str,bool]:
    # Inserta inmediatamente después de <h1 class="brand">…</h1>
    pat = re.compile(r'(<h1\b[^>]*class="[^"]*\bbrand\b[^"]*"[^>]*>.*?</h1>)', flags=re.S|re.I)
    if pat.search(s):
        return (pat.sub(r"\1\n" + tagline_block, s, count=1), True)
    return (s, False)

def insert_in_header(s: str) -> tuple[str,bool]:
    # Si hay <header>, lo mete adentro (al principio)
    pat = re.compile(r'(<header\b[^>]*>)', flags=re.I)
    if pat.search(s):
        return (pat.sub(r"\1\n" + tagline_block, s, count=1), True)
    return (s, False)

def insert_after_body(s: str) -> tuple[str,bool]:
    # Último recurso: al comienzo del body
    pat = re.compile(r'(<body\b[^>]*>)', flags=re.I)
    if pat.search(s):
        return (pat.sub(r"\1\n" + tagline_block, s, count=1), True)
    return (s, False)

# 4) Insertar una (y solo una) instancia
if 'id="tagline"' not in html:
    html2, ok = insert_after_brand(html)
    if not ok:
        html2, ok = insert_in_header(html)
    if not ok:
        html2, ok = insert_after_body(html)
    if ok:
        html = html2
        changed = True

# 5) Garantía: como máximo 1 tagline y 1 script
def keep_first_unique(s: str, needle: str) -> str:
    # conserva el primer match y borra los demás
    matches = list(re.finditer(needle, s, flags=re.I))
    if len(matches) <= 1:
        return s
    first = matches[0].span()
    out = s[:first[1]] + re.sub(needle, "", s[first[1]:], flags=re.I)
    return out

html = keep_first_unique(html, r'id="tagline"')
html = keep_first_unique(html, rf'id="{SCRIPT_ID}"')
html = keep_first_unique(html, rf'id="{STYLE_ID}"')

if not changed:
    print("OK: tagline ya estaba correcto (único y con rotador)."); sys.exit(0)

if not bak.exists():
    shutil.copyfile(IDX, bak)
IDX.write_text(html, encoding="utf-8")
print("patched: tagline único + rotador (backup creado en .bak)")
