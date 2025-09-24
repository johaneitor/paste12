#!/usr/bin/env bash
set -euo pipefail
HTML="${1:-frontend/index.html}"
ADS_CLIENT="${2:-ca-pub-9479870293204581}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
[[ -f "$HTML" ]] || { echo "ERROR: falta $HTML"; exit 2; }
cp -f "$HTML" "${HTML}.${TS}.reconcile.bak"
echo "[reconcile] Backup: ${HTML}.${TS}.reconcile.bak"

python - <<PY
import io, re, sys, html
p = "${HTML}"
s = io.open(p, "r", encoding="utf-8").read()
orig = s

def keep_first_tag_once(s, tag):
    # Mantiene solo el primer <tag>...</tag> y elimina duplicados adyacentes
    rx = re.compile(rf"<{tag}[^>]*>.*?</{tag}>", re.I|re.S)
    m = list(rx.finditer(s))
    if len(m) > 1:
        first = m[0]
        parts = [s[:first.end()]]
        # eliminar duplicados (pero deja el resto del documento)
        tail = s[first.end():]
        tail = rx.sub("", tail)
        return parts[0] + tail
    return s

# 1) Evitar títulos/subtítulos duplicados
for tag in ("h1","h2"):
    s = keep_first_tag_once(s, tag)

# 2) Asegurar bloque de métricas (views/likes/reports)
if 'class="views"' not in s:
    s = s.replace("</header>", '</header>\n<div id="p12-stats">👁️ <span class="views">0</span> · 👍 <span class="likes">0</span> · 🚩 <span class="reports">0</span></div>\n')

# 3) Normalizar AdSense: meta + script único en <head>, e idempotente
client = "${ADS_CLIENT}"
meta_rx = re.compile(r'<meta\s+name=["\\\']google-adsense-account["\\\']\s+content=["\\\']([^"\\\']+)["\\\']\s*/?>', re.I)
script_rx = re.compile(r'<script\s+async\s+src="https://pagead2\.googlesyndication\.com/pagead/js/adsbygoogle\.js\?client=([^"]+)"[^>]*>\s*</script>', re.I)

# Insertar <head> si faltara (muy raro)
if "<head" not in s.lower():
    s = s.replace("<html", "<html><head></head>", 1)

# Garantizar <meta ...>
if meta_rx.search(s):
    s = meta_rx.sub(f'<meta name="google-adsense-account" content="{client}"/>', s)
else:
    s = s.replace("<head", f"<head\n<meta name=\"google-adsense-account\" content=\"{client}\"/>", 1)

# Garantizar <script async ... client=...>
if script_rx.search(s):
    s = script_rx.sub(f'<script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client={client}" crossorigin="anonymous"></script>', s)
else:
    s = s.replace("<head", f"<head\n<script async src=\"https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client={client}\" crossorigin=\"anonymous\"></script>", 1)

# 4) Quitar registros de Service Worker para evitar UI vieja cacheada
s = re.sub(r'.*serviceWorker\.register.*\n?', '', s, flags=re.I)
s = re.sub(r'.*navigator\.serviceWorker.*\n?', '', s, flags=re.I)

# 5) Footer legal único con /terms y /privacy
has_terms = re.search(r'href=["\\\']/terms["\\\']', s, re.I)
has_priv  = re.search(r'href=["\\\']/privacy["\\\']', s, re.I)
footer_rx = re.compile(r"</footer>", re.I)
if not (has_terms and has_priv):
    if footer_rx.search(s):
        s = footer_rx.sub('  <a href="/terms">Términos y Condiciones</a> · <a href="/privacy">Política de Privacidad</a>\n</footer>', s)
    else:
        s = s.replace("</body>", '<footer style="margin-top:2rem;opacity:.85"><a href="/terms">Términos y Condiciones</a> · <a href="/privacy">Política de Privacidad</a></footer>\n</body>')

# 6) Evitar duplicados de “summary-enhancer” o hotfix previos
s = re.sub(r'<!--\s*summary-enhancer start\s*-->.*?<!--\s*summary-enhancer end\s*-->', '', s, flags=re.I|re.S)
# (si tienes una versión buena, podrías volver a insertarla aquí; por ahora solo limpiamos duplicados)

# 7) Compactar saltos de línea repetidos
s = re.sub(r'\n{3,}', '\n\n', s)

if s != orig:
    io.open(p, "w", encoding="utf-8").write(s)
    print("[reconcile] index.html actualizado")
else:
    print("[reconcile] index.html ya estaba OK")
PY

echo "[reconcile] Hecho."
