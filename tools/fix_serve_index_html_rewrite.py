#!/usr/bin/env python3
import re, sys, pathlib, py_compile

P = pathlib.Path("wsgiapp/__init__.py")
src = P.read_text(encoding="utf-8")

# 0) Asegurar import os (por si algún refactor lo quitó)
if not re.search(r'^\s*import\s+os\b', src, flags=re.M):
    src = re.sub(r'^(import[^\n]*\n)', r'\1import os\n', src, count=1, flags=re.M)

# 1) Reemplazar COMPLETO el cuerpo de def _serve_index_html() por una versión robusta
pat = re.compile(r'(?s)(^def\s+_serve_index_html\(\):\n)(.*?)(?=\n(?:def\s+|class\s+|#\s*---|#\s*===|$))', re.M)
m = pat.search(src)
if not m:
    print("no encontré def _serve_index_html()")
    sys.exit(1)

new_body = """\
    override = os.environ.get("WSGI_BRIDGE_INDEX")
    # Orden de preferencia: backend/static -> public -> frontend -> raíz del repo
    if override:
        candidates = [override]
    else:
        candidates = [
            os.path.join(_REPO_DIR, "backend", "static", "index.html"),
            os.path.join(_REPO_DIR, "public",  "index.html"),
            os.path.join(_REPO_DIR, "frontend","index.html"),
            os.path.join(_REPO_DIR, "index.html"),
        ]
    for p in candidates:
        if p and os.path.isfile(p):
            body = _try_read(p)
            if body is not None:
                ctype = mimetypes.guess_type(p)[0] or "text/html"
                status, headers, body = _html(200, body.decode("utf-8", "ignore"), f"{ctype}; charset=utf-8")
                # Forzar no-store en raíz servida por el bridge
                headers = [(k,v) for (k,v) in headers if k.lower()!="cache-control"] + [
                    ("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
                ]
                return status, headers, body

    # Fallback mínimo embebido (sin archivo)
    html = \"\"\"<!doctype html><html><head><meta charset="utf-8"><title>paste12</title></head>
<body style="font-family: system-ui, sans-serif; margin: 2rem;">
<h1>paste12</h1><p>Backend vivo (bridge fallback). Endpoints:</p>
<ul>
  <li><a href="/api/notes">/api/notes</a></li>
  <li><a href="/api/notes_fallback">/api/notes_fallback</a></li>
  <li><a href="/api/notes_diag">/api/notes_diag</a></li>
  <li><a href="/api/deploy-stamp">/api/deploy-stamp</a></li>
</ul>
</body></html>\"\"\"
    status, headers, body = _html(200, html)
    headers = [(k,v) for (k,v) in headers if k.lower()!="cache-control"] + [
        ("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
    ]
    return status, headers, body
"""

src2 = src[:m.start(2)] + new_body + src[m.end(2):]
P.write_text(src2, encoding="utf-8")

# 2) Validar sintaxis antes de commitear
try:
    py_compile.compile(str(P), doraise=True)
except Exception as e:
    print("py_compile failed:", e)
    sys.exit(2)

print("rewrote _serve_index_html() con indentación estable y no-store")
