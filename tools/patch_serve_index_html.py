#!/usr/bin/env python3
import re, sys, pathlib, py_compile, textwrap

P = pathlib.Path("wsgiapp/__init__.py")
s = P.read_text(encoding="utf-8")

# Reemplazamos SOLO el cuerpo de def _serve_index_html()
pat = re.compile(r'(def\s+_serve_index_html\(\):\s*\n)(?:.*?)(?=\n#|\n\w|\Z)', re.S)
m = pat.search(s)
if not m:
    print("ERROR: no encontré def _serve_index_html()")
    sys.exit(1)

body = textwrap.dedent("""
    override = os.environ.get("WSGI_BRIDGE_INDEX")
    if override:
        candidates = [override]
    else:
        candidates = [
            os.path.join(_REPO_DIR, "backend", "static", "index.html"),
            os.path.join(_REPO_DIR, "public", "index.html"),
            os.path.join(_REPO_DIR, "frontend", "index.html"),
            os.path.join(_REPO_DIR, "index.html"),
        ]
    for p in candidates:
        if p and os.path.isfile(p):
            body = _try_read(p)
            if body is not None:
                ctype = mimetypes.guess_type(p)[0] or "text/html"
                status, headers, body = _html(200, body.decode("utf-8", "ignore"), f"{ctype}; charset=utf-8")
                headers = [(k,v) for (k,v) in headers if k.lower()!="cache-control"]
                headers += [("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0"),
                            ("X-Index-Source", "bridge")]
                return status, headers, body
    html = \"\"\"<!doctype html>
<html><head><meta charset="utf-8"><title>paste12</title></head>
<body style="font-family: system-ui, sans-serif; margin: 2rem;">
<h1>paste12</h1>
<p>Backend vivo (bridge fallback). Endpoints:</p>
<ul>
  <li><a href="/api/notes">/api/notes</a></li>
  <li><a href="/api/notes_fallback">/api/notes_fallback</a></li>
  <li><a href="/api/notes_diag">/api/notes_diag</a></li>
  <li><a href="/api/deploy-stamp">/api/deploy-stamp</a></li>
</ul>
</body></html>\"\"\"
    status, headers, body = _html(200, html)
    headers = [(k,v) for (k,v) in headers if k.lower()!="cache-control"]
    headers += [("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0"),
                ("X-Index-Source", "bridge")]
    return status, headers, body
""").strip("\n")

s2 = s[:m.start(1)] + m.group(1) + body + "\n" + s[m.end():]
P.write_text(s2, encoding="utf-8")

# Sanity check: que compile
py_compile.compile(str(P), doraise=True)
print("patched: _serve_index_html reescrita de forma segura (+no-store +X-Index-Source)")
