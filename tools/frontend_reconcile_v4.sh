#!/usr/bin/env bash
set -euo pipefail
# Uso:
#   tools/frontend_reconcile_v4.sh <ADSENSE_CLIENT_ID>
# Ej:
#   tools/frontend_reconcile_v4.sh ca-pub-9479870293204581

CID="${1:-}"
if [[ -z "$CID" ]]; then
  echo "ERROR: debes pasar el Client ID de AdSense, ej: ca-pub-XXXX"; exit 2
fi

HTML="frontend/index.html"
[[ -f "$HTML" ]] || { echo "ERROR: falta $HTML"; exit 3; }

TS="$(date -u +%Y%m%d-%H%M%SZ)"
BAK="${HTML}.${TS}.reconcile.bak"
cp -f "$HTML" "$BAK"
echo "[reconcile] Backup: $BAK"

python3 - <<PY "$HTML" "$CID"
import io, sys, re
path, CID = sys.argv[1], sys.argv[2]
s = io.open(path, "r", encoding="utf-8").read()
orig = s
sl = s.lower()

def ensure_in_head(s, snippet):
    # Inserta justo después de <head> si existe; si no, al principio del doc.
    idx = s.lower().find("<head")
    if idx == -1:
        return snippet + "\n" + s
    # Ubicar cierre de la etiqueta <head> de apertura (>)
    gt = s.find(">", idx)
    if gt == -1: return snippet + "\n" + s
    return s[:gt+1] + "\n" + snippet + "\n" + s[gt+1:]

def once(s, needle, add_func):
    if needle.lower() in s.lower(): return s, False
    t = add_func(s); return t, True

# 1) Adsense <meta> (nuevo formato)
meta_tag = f'<meta name="google-adsense-account" content="{CID}">'
s, added_meta = once(s, 'name="google-adsense-account"', lambda x: ensure_in_head(x, meta_tag))

# 2) Adsense <script async> (pagead2 googlesyndication)
ads_script = f'<script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client={CID}" crossorigin="anonymous"></script>'
s, added_js = once(s, 'pagead2.googlesyndication.com/pagead/js/adsbygoogle.js', lambda x: ensure_in_head(x, ads_script))

# 3) SEO básico: description + canonical (si faltan)
desc_rx = re.compile(r'<meta\s+name=["\']description["\']', re.I)
if not desc_rx.search(s):
    s = ensure_in_head(s, '<meta name="description" content="Paste12 — notas efímeras y compartibles con métricas (vistas, likes, reports). Privado y simple.">')

canon_rx = re.compile(r'<link\s+rel=["\']canonical["\']', re.I)
if not canon_rx.search(s):
    # canonical por defecto a "/"
    s = ensure_in_head(s, '<link rel="canonical" href="/">')

# 4) Desregistrar/evitar Service Worker en el HTML (limpia restos)
s = re.sub(r'^\s*//\s*service\s*worker.*$', '', s, flags=re.I|re.M)
s = re.sub(r'navigator\.serviceWorker\.[^\n;]+[;\n]', '', s, flags=re.I)
s = re.sub(r'serviceWorker\.register\([^)]+\);?', '', s, flags=re.I)

# 5) Bloque de métricas (views/likes/reports) si falta .views
if 'class="views"' not in s.lower():
    # insertar cerca del inicio del body
    block = """<div id="p12-stats" class="stats" style="display:flex;gap:.75rem;align-items:center;margin:.5rem 0;font:14px/1.4 system-ui">
  <span class="views"   title="Vistas">👁️ 0</span>
  <span class="likes"   title="Likes">❤️ 0</span>
  <span class="reports" title="Reports">🚩 0</span>
</div>"""
    # Insertar después de <body>
    ib = s.lower().find("<body")
    if ib != -1:
        gt = s.find(">", ib)
        if gt != -1:
            s = s[:gt+1] + "\n" + block + "\n" + s[gt+1:]
        else:
            s = block + "\n" + s
    else:
        s = block + "\n" + s

# 6) Deduplicar títulos h1/h2 exactos seguidos (caso subtítulo duplicado)
def dedupe_headings(s):
    lines = s.splitlines()
    out = []
    last_norm = None
    for ln in lines:
        ln_low = ln.strip().lower()
        if ln_low.startswith("<h1") or ln_low.startswith("<h2"):
            # normalizar el texto interno (muy simple)
            txt = re.sub(r'<[^>]+>', '', ln_low)
            if txt == last_norm: 
                continue
            last_norm = txt
        else:
            last_norm = None
        out.append(ln)
    return "\n".join(out)

s = dedupe_headings(s)

# 7) Footer con /terms y /privacy (añadir si faltan enlaces)
has_terms  = re.search(r'href=["\']/terms["\']', s, re.I)
has_priv   = re.search(r'href=["\']/privacy["\']', s, re.I)
if not (has_terms and has_priv):
    foot = """<footer style="margin:2rem 0;opacity:.85">
  <a href="/terms">Términos y Condiciones</a> · <a href="/privacy">Política de Privacidad</a>
</footer>"""
    # Antes de </body> si existe
    idx_end = s.lower().rfind("</body>")
    if idx_end != -1:
        s = s[:idx_end] + foot + "\n" + s[idx_end:]
    else:
        s = s + "\n" + foot

# 8) Minilimpiezas de espacios en blanco repetidos (cosmético)
s = re.sub(r'\n{3,}', '\n\n', s)

if s != orig:
    io.open(path, "w", encoding="utf-8").write(s)
    print("[reconcile] index.html actualizado")
else:
    print("[reconcile] index.html ya estaba OK")
PY

echo "[reconcile] Hecho."
