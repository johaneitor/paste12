#!/usr/bin/env bash
set -euo pipefail

ADS_CLIENT="${1:-}"   # ej: ca-pub-9479870293204581
ROOT="$(pwd)"

# 1) Módulo de overlay
cat > frontend_overlay.py <<PY
import os, re, datetime
from wsgiref.util import FileWrapper

class FrontendOverlay:
    def __init__(self, app, root="frontend", ads_client=None):
        self.app = app
        self.root = os.path.abspath(root)
        self.ads_client = ads_client

    def _read(self, rel):
        p = os.path.join(self.root, rel)
        if not os.path.isfile(p):
            return None, None
        with open(p, "rb") as f:
            b = f.read()
        try:
            s = b.decode("utf-8", "strict")
            return s, "text/html; charset=utf-8"
        except Exception:
            return b, "application/octet-stream"

    def _inject_if_needed(self, html):
        s = html

        # hotfix marker
        if "p12-hotfix-v5" not in s:
            s = s.replace("<head>", "<head>\n<meta name=\\"x-p12-hotfix\\" content=\\"p12-hotfix-v5\\">", 1)

        # AdSense (solo si falta)
        if self.ads_client and "adsbygoogle.js" not in s:
            tag = f'<script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client={self.ads_client}" crossorigin="anonymous"></script>'
            s = re.sub(r"</head>", tag + "\n</head>", s, flags=re.I, count=1)

        # Bloque de métricas (solo si falta .views)
        if 'class="views"' not in s:
            block = '''
<div id="p12-stats" style="opacity:.9;margin-top:1rem;font-size:14px">
  <span class="views">0</span> 👁️
  <span class="likes">0</span> ❤️
  <span class="reports">0</span> 🚩
</div>'''
            if re.search(r"</footer>", s, flags=re.I):
                s = re.sub(r"</footer>", block + "\n</footer>", s, flags=re.I, count=1)
            else:
                s = re.sub(r"</body>", block + "\n</body>", s, flags=re.I, count=1)

        # Evitar SW/cachés viejas
        s = re.sub(r"serviceWorker\.register\(.*?\);\s*", "", s, flags=re.S)
        return s

    def __call__(self, environ, start_response):
        path = environ.get("PATH_INFO", "/") or "/"
        method = environ.get("REQUEST_METHOD", "GET").upper()

        if method == "GET" and path in ("/", "/terms", "/privacy"):
            rel = "index.html" if path == "/" else path.strip("/") + ".html"
            html, ctype = self._read(rel)
            if html is not None:
                if ctype.startswith("text/html"):
                    html = self._inject_if_needed(html)
                    body = html.encode("utf-8")
                else:
                    body = html
                headers = [
                    ("Content-Type", ctype),
                    ("Cache-Control", "no-store, max-age=0"),
                    ("X-Frontend-Overlay", "fe-v1"),
                    ("X-Served-File", rel),
                ]
                start_response("200 OK", headers)
                return [body]
        # Default: delega al app real
        return self.app(environ, start_response)
PY

# 2) Asegurar que hay index/terms/privacy simples (sin tocar los que ya tengas)
mkdir -p frontend
for f in index.html terms.html privacy.html; do
  [[ -f "frontend/$f" ]] || cat > "frontend/$f" <<HTML
<!doctype html><meta charset="utf-8">
<title>Paste12</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<body style="font:16px/1.5 system-ui,Segoe UI,Roboto,Arial;margin:1.5rem;max-width:56rem">
<h1>Paste12</h1>
<p>Página $f mínima. Reemplaza por tu versión completa cuando gustes.</p>
</body>
HTML
done

# 3) Parchear contract_shim para envolver la WSGI app
TARGET="contract_shim.py"
[[ -f "$TARGET" ]] || { echo "ERROR: falta $TARGET"; exit 2; }

python - <<PY
import io, re, os, sys
ads = os.environ.get("ADS_CLIENT_ENV") or ${ADS_CLIENT:+repr("${ADS_CLIENT}")} or ""
p = "contract_shim.py"
s = io.open(p, "r", encoding="utf-8").read()
orig = s

if "FrontendOverlay(" not in s:
    # importar y envolver después de 'application ='
    s = re.sub(r'(\napplication\s*=\s*.*\n)', r'\\1from frontend_overlay import FrontendOverlay\napplication = FrontendOverlay(application, root="frontend", ads_client="%s")\n' % ads, s, count=1, flags=re.S)

if s != orig:
    io.open(p, "w", encoding="utf-8").write(s)
    print("[overlay] contract_shim envuelto con FrontendOverlay")
else:
    print("[overlay] ya estaba aplicado")
PY

# 4) Compilación rápida
python -m py_compile contract_shim.py frontend_overlay.py || { echo "py_compile FAIL"; exit 3; }
echo "OK: FrontendOverlay instalado."
