#!/usr/bin/env bash
set -euo pipefail
HTML="frontend/index.html"
CID="${1:-ca-pub-9479870293204581}"

[[ -f "$HTML" ]] || { echo "ERROR: falta $HTML"; exit 1; }

TS="$(date -u +%Y%m%d-%H%M%SZ)"
cp -f "$HTML" "$HTML.$TS.reconcile.bak"
echo "[reconcile] Backup: $HTML.$TS.reconcile.bak"

python - <<PY
import io, re, sys
cid = sys.argv[1]
p="frontend/index.html"
s=io.open(p,"r",encoding="utf-8").read()
orig=s

lower = s.lower()

# 1) <meta name="google-adsense-account" content="ca-pub-...">
meta_rx = re.compile(r'<meta\s+name=["\']google-adsense-account["\']\s+content=["\']([^"\']+)["\']\s*/?>', re.I)
def upsert_meta(html):
    if meta_rx.search(html):
        return meta_rx.sub(f'<meta name="google-adsense-account" content="{cid}">', html)
    # insertar dentro de <head>
    return re.sub(r'(?i)<head([^>]*)>', r'<head\1>\n  <meta name="google-adsense-account" content="'+cid+'">', html, count=1)

s = upsert_meta(s)

# 2) Script de AdSense (único)
ads_rx = re.compile(r'<script[^>]+pagead/js/adsbygoogle\.js[^>]*>\s*</script>', re.I)
s = ads_rx.sub('', s)  # limpiar duplicados
s = re.sub(r'(?i)</head>',
           f'  <script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client={cid}" crossorigin="anonymous"></script>\n</head>',
           s, count=1)

# 3) Quitar duplicado de <h1>: dejar el primero, bajar el resto a <h2 class="subtitle">
def dedup_h1(html):
    h1_rx = re.compile(r'(?is)<h1\b[^>]*>.*?</h1>')
    all_h1 = list(h1_rx.finditer(html))
    if len(all_h1) <= 1:
        return html
    first_end = all_h1[0].end()
    tail = html[first_end:]
    tail = h1_rx.sub(lambda m: re.sub(r'(?is)^<h1', '<h2 class="subtitle"', re.sub(r'(?is)</h1>', '</h2>', m.group(0), count=1), count=1), tail)
    return html[:first_end] + tail

s = dedup_h1(s)

# 4) Asegurar <span class="views"> en la tarjeta principal
if 'class="views"' not in s.lower():
    s = re.sub(r'(?is)(<h1\b[^>]*>.*?</h1>)', r'\1\n<p class="meta">Vistas: <span class="views">0</span></p>', s, count=1)

# 5) Footer legal con /terms /privacy si faltan
need_terms = re.search(r'href=["\']/terms["\']', s, re.I) is None
need_priv  = re.search(r'href=["\']/privacy["\']', s, re.I) is None
if need_terms or need_priv:
    footer = '<footer style="margin-top:2rem;opacity:.85">'
    if need_terms: footer += ' <a href="/terms">Términos y Condiciones</a>'
    if need_priv:  footer += ' · <a href="/privacy">Política de Privacidad</a>'
    footer += '</footer>'
    s = re.sub(r'(?i)</body>', footer + '\n</body>', s, count=1)

# 6) Eliminar SW antiguo que ensucia caché
s = re.sub(r'(?i)<script[^>]*>\s*if\s*\(\s*[\'"]serviceWorker[\'"]\s*in\s*navigator\)\s*\{.*?\}\s*</script>', '', s, flags=re.S)
s = re.sub(r'(?i)navigator\.serviceWorker\.register\([^)]*\)\s*;?', '', s)

if s != orig:
    io.open(p,"w",encoding="utf-8").write(s)
    print("mod: index.html reconciliado")
else:
    print("info: index.html ya estaba OK")
PY "$CID"

echo "OK: Frontend reconciliado."
