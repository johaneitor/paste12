#!/usr/bin/env bash
set -euo pipefail

WSGI_FILE="wsgi.py"
CLIENT_ID="${1:-ca-pub-9479870293204581}"

[[ -f "$WSGI_FILE" ]] || { echo "❌ No existe $WSGI_FILE"; exit 1; }

if grep -q "### BEGIN:P12_ADSENSE_INJECTOR" "$WSGI_FILE"; then
  echo "✔ Inyector ya presente en $WSGI_FILE (no hago nada)"; exit 0;
fi

TS="$(date +%Y%m%d-%H%M%SZ)"
cp -f "$WSGI_FILE" "$WSGI_FILE.bak.$TS"

cat >> "$WSGI_FILE" <<'PYCODE'
# ### BEGIN:P12_ADSENSE_INJECTOR (no editar dentro de este bloque)
import re
from typing import Iterable, Callable, Tuple

_P12_SNIPPET = None  # será rellenado por el shell script
class _P12HeadInject:
    def __init__(self, app, snippet_html: str):
        self.app = app
        # normalizamos a bytes una sola vez
        self.snippet = (snippet_html or "").encode("utf-8")

    def __call__(self, environ, start_response):
        state = {}
        def _capture_start(status: str, headers: list, exc_info=None):
            state["status"] = status
            state["headers"] = list(headers)
            state["exc_info"] = exc_info
            # devolvemos un no-op write (WSGI antiguo)
            return lambda _chunk: None

        result = self.app(environ, _capture_start)

        # consumimos el iterable (respuestas pequeñas como index)
        try:
            body = b"".join(result)
        finally:
            if hasattr(result, "close"):
                try: result.close()
                except Exception: pass

        headers = state.get("headers", [])
        status  = state.get("status", "200 OK")
        exc     = state.get("exc_info")

        # ¿HTML?
        ctype = ""
        for k, v in headers:
            if k.lower() == "content-type":
                ctype = v or ""
                break

        if "text/html" in ctype and self.snippet:
            try:
                text = body.decode("utf-8", "ignore")
                # ya insertado?
                if "pagead2.googlesyndication.com/pagead/js/adsbygoogle.js" not in text:
                    # insertamos antes de </head> (case-insensitive)
                    m = re.search(r"</head>", text, flags=re.IGNORECASE)
                    if m:
                        pos = m.start()
                        text = text[:pos] + _P12_SNIPPET + text[pos:]
                        body = text.encode("utf-8")
                        # quitamos Content-Length si existía (chunked/auto)
                        headers = [(k, v) for (k, v) in headers if k.lower() != "content-length"]
            except Exception:
                pass  # si algo falla, devolvemos tal cual

        start_response(status, headers, exc)
        return [body]

# ### END:P12_ADSENSE_INJECTOR
PYCODE

# Rellenar el snippet con el client id recibido
python - <<PY
from pathlib import Path
p = Path("$WSGI_FILE")
s = p.read_text(encoding="utf-8")
snippet = (
    '<script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=%s"\\n'
    '     crossorigin="anonymous"></script>\\n'
) % ("$CLIENT_ID",)
s = s.replace("_P12_SNIPPET = None", "_P12_SNIPPET = " + repr(snippet))
# envolver la aplicación si existe el símbolo `application`
if "application =" in s and "P12HeadInject" not in s and "_P12HeadInject(" not in s:
    # añadimos el wrap al final del archivo
    s += '\n# Activamos el inyector en runtime\ntry:\n' \
         '    application = _P12HeadInject(application, _P12_SNIPPET)\n' \
         'except Exception:\n' \
         '    pass\n'
Path("$WSGI_FILE").write_text(s, encoding="utf-8")
print("✔ Inyector añadido a", p)
PY

python -m py_compile "$WSGI_FILE" && echo "✓ py_compile $WSGI_FILE"
