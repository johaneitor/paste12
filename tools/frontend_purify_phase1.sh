#!/usr/bin/env bash
set -euo pipefail

HTML="frontend/index.html"
PUB_ID="${1:-${ADSENSE_PUB_ID:-ca-pub-9479870293204581}}"

[[ -f "$HTML" ]] || { echo "ERROR: falta $HTML"; exit 1; }

TS="$(date -u +%Y%m%d-%H%M%SZ)"
BAK="frontend/index.$TS.phase1.bak"
cp -f "$HTML" "$BAK"
echo "Backup: $BAK"

python - <<'PY'
import io, re, sys, os

html_path = "frontend/index.html"
pub_id = os.environ.get("PUB_ID", "ca-pub-9479870293204581")

s = io.open(html_path, "r", encoding="utf-8").read()
orig = s

# 1) Asegurar AdSense en <head>
ads_re = re.compile(r'pagead2\.googlesyndication\.com/.*/adsbygoogle\.js\?client=ca-pub-', re.I)
if not ads_re.search(s):
    ads = (
        f'<script async '
        f'src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client={pub_id}" '
        f'crossorigin="anonymous"></script>\n'
    )
    s = re.sub(r'</head>', ads + '</head>', s, flags=re.I, count=1)

# 2) Insertar span.views si falta (bloque mínimo al final del body)
if not re.search(r'<span[^>]*class="[^"]*\\bviews\\b', s, re.I):
    stats = (
        '\n<div id="p12-stats" style="margin:.75rem 0;font:14px system-ui;">'
        'Views: <span class="views">0</span> · '
        'Likes: <span class="likes">0</span> · '
        'Reports: <span class="reports">0</span>'
        '</div>\n'
    )
    s = re.sub(r'</body>', stats + '</body>', s, flags=re.I, count=1)

# 3) Quitar service worker refs para evitar caché vieja
s = re.sub(r'.*serviceWorker\.register.*\n?', '', s, flags=re.I)
s = re.sub(r'.*navigator\.serviceWorker.*\n?', '', s, flags=re.I)

# 4) Deduplicar H1 (dejar el primero; los siguientes reemplazarlos por comentario)
h1_pat = re.compile(r'<h1\b[^>]*>.*?</h1>', re.I|re.S)
found = list(h1_pat.finditer(s))
if len(found) > 1:
    # mantener el primero
    first = found[0]
    out = []
    last = 0
    out.append(s[:first.end()])
    last = first.end()
    for m in found[1:]:
        out.append(s[last:m.start()])
        out.append('<!-- removed duplicate h1 -->')
        last = m.end()
    out.append(s[last:])
    s = ''.join(out)

# Limpieza de saltos excesivos
s = re.sub(r'\n{3,}', '\n\n', s)

if s != orig:
    io.open(html_path, "w", encoding="utf-8").write(s)
    print("OK: Fase 1 aplicada en index.html")
else:
    print("INFO: Fase 1 no cambió nada (ya estaba OK)")
PY
