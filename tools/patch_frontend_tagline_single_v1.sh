#!/usr/bin/env bash
set -euo pipefail
HTML="frontend/index.html"
[[ -f "$HTML" ]] || { echo "ERROR: falta $HTML"; exit 1; }
TS="$(date -u +%Y%m%d-%H%M%SZ)"
BAK="frontend/index.$TS.tagline.bak"
cp -f "$HTML" "$BAK"; echo "[backup] $BAK"

python - <<'PY'
import io,re
p="frontend/index.html"
s=io.open(p,'r',encoding='utf-8').read()
orig=s

# 1) Unificar a UN solo elemento: <h2 id="tagline" class="tagline"></h2>
#    - borrar <h2 id="tagline-rot"> y convertirlo a <h2 id="tagline">
s=re.sub(r'<h2[^>]*id=["\']tagline-rot["\'][^>]*>.*?</h2>\s*', '', s, flags=re.I|re.S)
if not re.search(r'id=["\']tagline["\']', s, re.I):
    # si no hay, lo insertamos después del H1 de marca
    s=re.sub(r'(</h1>)', r'\1\n  <h2 id="tagline" class="tagline"></h2>', s, count=1, flags=re.I)

# 2) Eliminar <p id="tagline" ...> duplicado si existe o convertirlo a h2
def repl_p(m):
    return '<h2 id="tagline" class="tagline">{}</h2>'.format(m.group('inner').strip())
s=re.sub(r'<p[^>]*id=["\']tagline["\'][^>]*>(?P<inner>.*?)</p>', repl_p, s, flags=re.I|re.S)

# 3) CSS: asegurar estilo .tagline sobrio (una sola definición)
if 'id="tagline-style"' not in s:
    s=s.replace('</style>', '</style>\n<style id="tagline-style">#tagline{margin:.25rem 0 0;opacity:.9;line-height:1.25;font-weight:600;color:#17323a}</style>', 1)

# 4) Rotador: que escriba en #tagline (no #tagline-rot)
s=re.sub(r"getElementById\(['\"]tagline-rot['\"]\)", "getElementById('tagline')", s)

# 5) Asegurar AdSense en <head>
if 'pagead2.googlesyndication.com/pagead/js/adsbygoogle.js' not in s:
    s=s.replace('</head>', '<script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=ca-pub-9479870293204581" crossorigin="anonymous"></script>\n</head>')

if s!=orig:
    io.open(p,'w',encoding='utf-8').write(s)
    print("OK: tagline unificado y AdSense verificado.")
else:
    print("INFO: ya estaba OK.")
PY
echo "Hecho."
