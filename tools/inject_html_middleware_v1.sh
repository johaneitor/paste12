#!/usr/bin/env bash
# Inserta un middleware WSGI que garantiza:
#  - <span class="views">…</span> dentro del bloque #p12-stats
#  - <script async src="...adsbygoogle.js?client=CA_PUB"> en <head>
# Seguro, idempotente, sin depender de Flask internals.
set -euo pipefail
CA_PUB="${1:-ca-pub-9479870293204581}"  # Cambiable por argumento

FILE="contract_shim.py"
[ -f "$FILE" ] || { echo "No existe $FILE"; exit 1; }

# Si ya lo aplicamos, salimos
if grep -q "class _P12HtmlInjectMiddleware" "$FILE"; then
  echo "✔ Middleware ya presente en $FILE (skip)."
  exit 0
fi

python3 - <<PY
from pathlib import Path
p = Path("$FILE")
src = p.read_text(encoding="utf-8")

snippet = f"""
# == P12: HTML inject middleware (views + AdSense) ==
class _P12HtmlInjectMiddleware:
    _ADS = '<script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client={CA_PUB}" crossorigin="anonymous"></script>'
    _VIEWS_BLOCK = (
        '<div id="p12-stats" class="stats">'
        '<span class="views" data-views="0">👁️ <b>0</b></span>'
        '<span class="likes" data-likes="0">❤️ <b>0</b></span>'
        '<span class="reports" data-reports="0">🚩 <b>0</b></span>'
        '</div>'
    )
    def __init__(self, app):
        self.app = app

    def __call__(self, environ, start_response):
        captured = {}
        def _sr(status, headers, exc_info=None):
            captured["status"] = status
            captured["headers"] = list(headers)
            captured["exc_info"] = exc_info
            body_parts = []
            captured["body_parts"] = body_parts
            return body_parts.append

        app_iter = self.app(environ, _sr)
        body = b''.join(captured.get("body_parts", []))
        try:
            for chunk in app_iter:
                body += chunk
        finally:
            if hasattr(app_iter, "close"):
                app_iter.close()

        # Content-Type?
        ct = ""
        for k, v in captured["headers"]:
            if k.lower() == "content-type":
                ct = v or ""
                break

        if "text/html" in ct.lower() and body:
            try:
                html = body.decode("utf-8", "ignore")
                # Garantizar AdSense en <head> si falta
                if "googlesyndication.com/pagead/js/adsbygoogle.js" not in html:
                    if "</head>" in html:
                        html = html.replace("</head>", self._ADS + "\\n</head>", 1)
                # Garantizar bloque .views dentro de #p12-stats
                if 'class="views"' not in html:
                    if "</body>" in html:
                        # intenta insertar antes de </body>. Si ya existe #p12-stats,
                        # solo añade el span si no está; si no existe, mete el bloque completo.
                        if 'id="p12-stats"' in html:
                            # insertar span.views dentro de #p12-stats (heurística simple)
                            html = html.replace('id="p12-stats"', 'id="p12-stats"', 1)
                            if 'class="views"' not in html:
                                html = html.replace('id="p12-stats"', 'id="p12-stats">'+self._VIEWS_BLOCK, 1)
                        else:
                            html = html.replace("</body>", self._VIEWS_BLOCK + "\\n</body>", 1)
                body = html.encode("utf-8", "ignore")
                # Ajustar Content-Length
                new_headers = []
                for k, v in captured["headers"]:
                    if k.lower() != "content-length":
                        new_headers.append((k, v))
                new_headers.append(("Content-Length", str(len(body))))
                captured["headers"] = new_headers
            except Exception:
                # Si algo falla, servimos el body original
                pass

        start_response(captured["status"], captured["headers"], captured["exc_info"])
        return [body]

# Wrap seguro si existe 'application'
try:
    application  # noqa: F821
    application = _P12HtmlInjectMiddleware(application)  # type: ignore
except NameError:
    # Si en su lugar hay 'app' (Flask), envolver su .wsgi_app
    try:
        app  # noqa: F821
        app.wsgi_app = _P12HtmlInjectMiddleware(app.wsgi_app)  # type: ignore
        application = app  # export canónico
    except NameError:
        # No pudimos detectar el objeto WSGI; dejamos el archivo igual.
        pass
"""

p.write_text(src.rstrip() + "\n\n" + snippet, encoding="utf-8")
print("✔ Middleware inyectado en", p)
PY

python3 - <<PY
import py_compile
py_compile.compile("contract_shim.py", doraise=True)
print("✓ py_compile OK")
PY
echo "Listo. Reinicia o redeploy en Render."
