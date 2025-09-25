#!/usr/bin/env bash
# Uso: tools/frontend_reconcile_v4.sh <ADSENSE_CLIENT_ID>
# Ej.: tools/frontend_reconcile_v4.sh ca-pub-9479870293204581
set -euo pipefail

ADS_CLIENT="${1:-}"
HTML="frontend/index.html"
[[ -n "$ADS_CLIENT" ]] || { echo "ERROR: falta client AdSense"; exit 2; }
[[ -f "$HTML" ]] || { echo "ERROR: falta $HTML"; exit 3; }

TS="$(date -u +%Y%m%d-%H%M%SZ)"
BAK="$HTML.$TS.reconcile.bak"
cp -f "$HTML" "$BAK"
echo "[reconcile] Backup: $BAK"

python - <<PY
import io, re, sys, os
p = "$HTML"
s = io.open(p, "r", encoding="utf-8").read()
orig = s

def ensure_in_head(snippet: str):
    global s
    head_close = re.search(r"</head\s*>", s, flags=re.I)
    if head_close and snippet not in s:
        s = s[:head_close.start()] + snippet + "\n" + s[head_close.start():]

def ensure_meta(name, content):
    global s
    rx = re.compile(rf'<meta\s+name=[\'"]{re.escape(name)}[\'"]\s+content=[\'"][^\'"]+[\'"]\s*/?>', re.I)
    if not rx.search(s):
        ensure_in_head(f'<meta name="{name}" content="{content}">')

def ensure_tag(rx, snippet):
    global s
    if not re.search(rx, s, re.I|re.S):
        ensure_in_head(snippet)

# 1) Quitar registros de Service Worker (evitar caches viejas)
s = re.sub(r'(?is).*?navigator\.serviceWorker.*?\n', '', s)
s = re.sub(r'(?is).*?serviceWorker\.register.*?\n', '', s)

# 2) Asegurar meta & script de AdSense
ensure_meta("google-adsense-account", "${ADS_CLIENT}")
ensure_tag(r'pagead2\.googlesyndication\.com/pagead/js/adsbygoogle\.js\?client=',
          f'<script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=${ADS_CLIENT}" crossorigin="anonymous"></script>')

# 3) Canonical + robots (SEO mínimos)
ensure_meta("robots", "index,follow")
if not re.search(r'<link\s+rel=["\']canonical["\']', s, re.I):
    ensure_in_head('<link rel="canonical" href="/">')

# 4) Deduplicar H1 (dejar solo el primero; si no hay, crear uno simple)
h1_iter = list(re.finditer(r'(?is)<h1[^>]*>.*?</h1>', s))
if not h1_iter:
    # Insertar h1 después de <body>
    s = re.sub(r'(?is)<body([^>]*)>', r'<body\1>\n<h1>Paste12</h1>', s, count=1)
else:
    first_h1 = h1_iter[0].group(0)
    # borrar TODOS los h1
    s = re.sub(r'(?is)\s*<h1[^>]*>.*?</h1>', '', s)
    # re-insertar el primero después de <body>
    if re.search(r'(?is)<body[^>]*>', s):
        s = re.sub(r'(?is)<body([^>]*)>', lambda m: m.group(0) + "\n" + first_h1, s, count=1)
    else:
        s = first_h1 + "\n" + s

# 5) Bloque de métricas (views/likes/reports)
need_views = not re.search(r'class=["\']views["\']', s, re.I)
need_stats = not re.search(r'id=["\']p12-stats["\']', s, re.I)
if need_views or need_stats:
    stats = """
<section id="p12-stats" style="margin:.75rem 0; font-size:.9rem; opacity:.9">
  <span class="views" title="Vistas">👁️ <b>0</b></span> ·
  <span class="likes" title="Me gusta">❤️ <b>0</b></span> ·
  <span class="reports" title="Reportes">🚩 <b>0</b></span>
</section>
""".strip()
    # Insertarlo después del H1
    s = re.sub(r'(?is)(<h1[^>]*>.*?</h1>)', r'\1\n' + stats, s, count=1)

# 6) Footer legal (terms/privacy) si faltan
has_terms  = re.search(r'href=["\']/terms["\']', s, re.I) is not None
has_priv   = re.search(r'href=["\']/privacy["\']', s, re.I) is not None
if not (has_terms and has_priv):
    if re.search(r'</footer\s*>', s, re.I):
        def ensure_link(ss, text, href):
            if re.search(re.escape(href), ss, re.I): return ss
            return re.sub(r'(?is)</footer\s*>', f'  <a href="{href}">{text}</a>\n</footer>', ss, count=1)
        s = ensure_link(s, "Términos y Condiciones", "/terms")
        s = ensure_link(s, "Política de Privacidad", "/privacy")
    else:
        s = re.sub(r'(?is)</body\s*>',
                   '\n<footer style="margin-top:2rem;opacity:.85">'
                   '<a href="/terms">Términos y Condiciones</a> · '
                   '<a href="/privacy">Política de Privacidad</a>'
                   '</footer>\n</body>', s, count=1)

# 7) Marcar versión para verificación visual
stamp = f"hotfix v5 {os.environ.get('TZ','UTC')}"
if "hotfix v5" not in s:
    s = s.replace("</body>", f"\n<!-- {stamp} -->\n</body>")

# Limpieza de espacios
s = re.sub(r'\n{3,}', '\n\n', s)

if s != orig:
    io.open(p, "w", encoding="utf-8").write(s)
    print("mod: index.html actualizado")
else:
    print("INFO: index.html ya estaba OK")
PY

echo "[reconcile] Hecho."
