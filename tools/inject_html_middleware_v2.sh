#!/usr/bin/env bash
# Uso: tools/inject_html_middleware_v2.sh ca-pub-XXXXXXXXXXXX
# Idempotente: si ya está, no vuelve a insertarlo.

set -euo pipefail
CA_PUB="${1:-ca-pub-9479870293204581}"
FILE="contract_shim.py"

[ -f "$FILE" ] || { echo "No existe $FILE"; exit 1; }

# si ya existe, salimos
if grep -q "_P12HtmlInjectMiddleware" "$FILE"; then
  echo "✔ Middleware ya presente en $FILE (skip)."
  python3 - <<PY
import py_compile; py_compile.compile("$FILE", doraise=True); print("✓ py_compile OK")
PY
  exit 0
fi

# Append del middleware (sin f-strings)
cat >> "$FILE" <<PY

# == P12: HTML inject middleware (views + AdSense) ==
class _P12HtmlInjectMiddleware:
    ADS = '<script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=${CA_PUB}" crossorigin="anonymous"></script>'
    VIEWS_BLOCK = (
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
        body_parts = []

        def _sr(status, headers, exc_info=None):
            captured["status"] = status
            captured["headers"] = list(headers)
            captured["exc_info"] = exc_info
            # devolvemos un "write" que acumula
            return body_parts.append

        app_iter = self.app(environ, _sr)
        try:
            for chunk in app_iter:
                body_parts.append(chunk)
        finally:
            if hasattr(app_iter, "close"):
                app_iter.close()

        body = b"".join(body_parts)

        # Detección de Content-Type
        ct = ""
        for k, v in captured.get("headers", []):
            if k.lower() == "content-type":
                ct = v or ""
                break

        # Inyección sólo si es HTML
        if "text/html" in (ct or "").lower() and body:
            try:
                html = body.decode("utf-8", "ignore")

                # Asegurar AdSense en <head>
                if "pagead/js/adsbygoogle.js?client=" not in html:
                    if "</head>" in html:
                        html = html.replace("</head>", self.ADS + "\\n</head>", 1)

                # Asegurar .views (bloque completo si no está)
                if 'class="views"' not in html:
                    if "</body>" in html:
                        html = html.replace("</body>", self.VIEWS_BLOCK + "\\n</body>", 1)
                    else:
                        html = html + self.VIEWS_BLOCK

                body = html.encode("utf-8", "ignore")

                # Ajustar Content-Length
                new_headers = []
                for k, v in captured["headers"]:
                    if k.lower() != "content-length":
                        new_headers.append((k, v))
                new_headers.append(("Content-Length", str(len(body))))
                captured["headers"] = new_headers
            except Exception:
                pass  # si algo falla, servimos tal cual

        start_response(captured["status"], captured["headers"], captured["exc_info"])
        return [body]

# Envolver aplicación WSGI si existe 'application' o 'app'
try:
    _exists = application  # noqa: F821
    application = _P12HtmlInjectMiddleware(application)  # type: ignore
except NameError:
    try:
        _exists = app  # noqa: F821
        try:
            # Flask: encadenar sobre wsgi_app
            app.wsgi_app = _P12HtmlInjectMiddleware(app.wsgi_app)  # type: ignore
            application = app  # export canónico
        except Exception:
            # fallback: envolver app directamente
            application = _P12HtmlInjectMiddleware(app)  # type: ignore
    except NameError:
        # No pudimos detectar el objeto WSGI; se mantendrá sin wrap
        pass

PY

# Compila para asegurar sintaxis
python3 - <<PY
import py_compile
py_compile.compile("$FILE", doraise=True)
print("✓ py_compile OK")
PY

echo "✔ Middleware inyectado en $FILE"
echo "→ Haz deploy en Render con el Start Command sugerido."
