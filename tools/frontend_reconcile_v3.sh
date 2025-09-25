#!/usr/bin/env bash
set -euo pipefail
FILE="${1:-frontend/index.html}"
ADS="${2:-ca-pub-XXXXXXXXXXXXXXXX}"
[[ -f "$FILE" ]] || { echo "ERROR: falta $FILE"; exit 2; }
TS="$(date -u +%Y%m%d-%H%M%SZ)"
BAK="$FILE.$TS.reconcile.bak"
cp -f "$FILE" "$BAK"
echo "[reconcile] Backup: $BAK"

python - <<PY
import io, re, sys
p = sys.argv[1]
ads = sys.argv[2]
s = io.open(p, 'r', encoding='utf-8').read()
orig = s

# 1) <meta name="google-adsense-account" content="ca-pub-...">
meta_rx = re.compile(r'<meta\s+name=(["\'])google-adsense-account\1\s+content=(["\'])(.*?)\2\s*/?>', re.I)
if meta_rx.search(s):
    s = meta_rx.sub(lambda m: f'<meta name="google-adsense-account" content="{ads}">', s, count=1)
else:
    # insertar tras <head>
    s = re.sub(r'(?i)<head([^>]*)>', lambda m: f'<head{m.group(1)}>\n<meta name="google-adsense-account" content="{ads}">', s, count=1)

# 2) Asegurar bloque de métricas con <span class="views">
if re.search(r'<span[^>]+class=(["\']).*?\\bviews\\b.*?\\1', s):
    pass
else:
    # insertar un bloque compacto antes de cierre de header o al inicio del main
    injected = '\n<div id="p12-stats" style="opacity:.9;font:14px system-ui,Segoe UI,Roboto,Arial">\n  <span class="views" title="Vistas">0</span>\n  · <span class="likes" title="Me gusta">0</span>\n  · <span class="reports" title="Reportes">0</span>\n</div>\n'
    if re.search(r'</header>', s, re.I):
        s = re.sub(r'(?i)</header>', injected + '</header>', s, count=1)
    elif re.search(r'(?i)<main', s):
        s = re.sub(r'(?i)<main([^>]*)>', lambda m: f'<main{m.group(1)}>{injected}', s, count=1)
    else:
        s = s.replace('</body>', injected + '\n</body>')

# 3) Pequeña limpieza de duplicados obvios del <title>/<h1> (cuando están idénticos)
title_m = re.search(r'(?is)<title>(.*?)</title>', s)
h1_m    = re.search(r'(?is)<h1[^>]*>(.*?)</h1>', s)
if title_m and h1_m and title_m.group(1).strip()==h1_m.group(1).strip():
    # mantener <title>, dejar <h1> como subtítulo (h2) para evitar “doble título”
    s = re.sub(r'(?is)<h1([^>]*)>(.*?)</h1>', r'<h2\1>\2</h2>', s, count=1)

if s != orig:
    io.open(p, 'w', encoding='utf-8').write(s)
    print("OK: index reconciliado (AdSense + views + título).")
else:
    print("INFO: index ya estaba OK.")
PY
"$FILE" "$ADS"
