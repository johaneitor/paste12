#!/usr/bin/env bash
set -euo pipefail

HTML="${1:-frontend/index.html}"
ADS_ID="${2:-}"
BASE="${3:-}"

[[ -f "$HTML" ]] || { echo "ERROR: falta $HTML"; exit 2; }

TS="$(date -u +%Y%m%d-%H%M%SZ)"
BAK="$HTML.$TS.reconcile.bak"
cp -f "$HTML" "$BAK"
echo "[reconcile] Backup: $BAK"

python - <<'PY'
import io, re, sys, html

path = sys.argv[1]
ads_id = sys.argv[2]

s = io.open(path, 'r', encoding='utf-8').read()
orig = s

# --- helpers
def ensure_in_head(html_str, snippet):
    # inserta antes de </head> (case-insensitive), si no existe
    if re.search(re.escape(snippet), html_str, re.I):
        return html_str
    m = re.search(r'</head\s*>', html_str, re.I)
    if m:
        i = m.start()
        return html_str[:i] + snippet + html_str[i:]
    # si no hay <head>, lo creamos
    return "<head>"+snippet+"</head>"+html_str

def ensure_after(tag_rx, html_str, snippet):
    m = re.search(tag_rx, html_str, re.I|re.S)
    if not m:
        return html_str
    end = m.end()
    return html_str[:end] + snippet + html_str[end:]

def drop_dupe_titles(html_str):
    # Mantener el primer <h1>; eliminar h1/h2 consecutivos duplicados (mismo texto normalizado)
    def norm(t): return re.sub(r'\s+', ' ', html.unescape(t)).strip().lower()
    # capturar tags h1/h2 con su contenido
    tags = list(re.finditer(r'<h([12])[^>]*>(.*?)</h\1\s*>', html_str, re.I|re.S))
    keep = [True]*len(tags)
    seen = set()
    for i, m in enumerate(tags):
        text = norm(re.sub('<[^>]+>', '', m.group(2)))
        key = (m.group(1), text)
        if text and key in seen:
            keep[i] = False
        else:
            seen.add(key)
    # reconstruir
    out = []
    last = 0
    for k,(m,ok) in enumerate(zip(tags, keep)):
        out.append(html_str[last:m.start()])
        if ok:
            out.append(m.group(0))
        last = m.end()
    out.append(html_str[last:])
    return ''.join(out)

def ensure_views_span(html_str):
    # Si ya existe .views, no tocar
    if re.search(r'<span[^>]*\bclass\s*=\s*"[^"]*\bviews\b[^"]*"[^>]*>', html_str, re.I):
        return html_str
    # Buscar bloque de métricas existente; si no, crear contenedor mínimo
    # 1) Intentar dentro de #p12-stats
    if re.search(r'id\s*=\s*"p12-stats"', html_str, re.I):
        return re.sub(r'(<div[^>]*id\s*=\s*"p12-stats"[^>]*>)',
                      r'\1<span class="views" title="Vistas">0</span>',
                      html_str, count=1, flags=re.I)
    # 2) Insertar al inicio del <main> si existe
    if re.search(r'<main[^>]*>', html_str, re.I):
        return re.sub(r'(<main[^>]*>)',
                      r'\1<div id="p12-stats" class="stats"><span class="views" title="Vistas">0</span></div>',
                      html_str, count=1, flags=re.I)
    # 3) Antes de </body>
    return re.sub(r'(</body\s*>)',
                  r'<div id="p12-stats" class="stats"><span class="views" title="Vistas">0</span></div>\n\1',
                  html_str, count=1, flags=re.I)

# --- 1) AdSense <meta> + <script> (head)
if ads_id:
    meta_rx = re.compile(r'<meta\s+name=["\']google-adsense-account["\']\s+content=["\']([^"\']+)["\']\s*/?>', re.I)
    tag_rx  = re.compile(r'<script[^>]+pagead2\.googlesyndication\.com/pagead/js/adsbygoogle\.js[^>]*\?client=([^"&\']+)[^>]*></script>', re.I)

    # meta
    if meta_rx.search(s):
        s = meta_rx.sub(lambda m: m.group(0).replace(m.group(1), ads_id), s, count=1)
    else:
        s = ensure_in_head(s, f'\n<meta name="google-adsense-account" content="{ads_id}"/>\n')

    # script
    if not tag_rx.search(s):
        script = f'\n<script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client={ads_id}" crossorigin="anonymous"></script>\n'
        s = ensure_in_head(s, script)

# --- 2) Quitar SW/caché viejo
s = re.sub(r'\s*<script[^>]*>\s*if\s*\(\s*[\'"]serviceWorker', '', s, flags=re.I)
s = re.sub(r'\s*navigator\.serviceWorker\.register\([^)]*\);\s*', '', s, flags=re.I)

# --- 3) Títulos duplicados
s = drop_dupe_titles(s)

# --- 4) Asegurar <span class="views">
s = ensure_views_span(s)

# --- 5) Limpieza leve de comentarios legado
s = re.sub(r'<!--\s*(LEGACY|OLD|TODO-OLD|HOTFIX-\w+)\s*-->','', s, flags=re.I)

if s != orig:
    io.open(path, 'w', encoding='utf-8').write(s)
    print("[reconcile] index modificado")
else:
    print("[reconcile] index ya estaba OK")
PY
PY_ARGS
"$HTML" "$ADS_ID"

# --- quitar referencias SW también con sed nivel archivo (doble seguro)
sed -i.bak '/serviceWorker\.register/d' "$HTML" || true
sed -i.bak '/navigator\.serviceWorker/d' "$HTML" || true

echo "[reconcile] listo."
