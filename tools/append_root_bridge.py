import re, sys, pathlib
P = pathlib.Path("wsgiapp/__init__.py")
s = P.read_text(encoding="utf-8")

changed = []

# Asegurar import os
if not re.search(r'^\s*import\s+os\b', s, flags=re.M):
    s = re.sub(r'^(import[^\n]*\n)', r'\1import os\n', s, count=1, flags=re.M)
    changed.append("import os")

# Inyectar middleware final (si no existe)
if "def _root_force_mw(" not in s:
    s += r"""

# --- middleware final: fuerza '/' del bridge si FORCE_BRIDGE_INDEX está activo ---
def _root_force_mw(inner):
    def _mw(environ, start_response):
        path   = environ.get("PATH_INFO", "") or ""
        method = (environ.get("REQUEST_METHOD", "GET") or "GET").upper()
        forced = os.getenv("FORCE_BRIDGE_INDEX","").strip().lower() in ("1","true","yes","on")
        if forced and path in ("/","/index.html") and method in ("GET","HEAD"):
            status, headers, body = _serve_index_html()
            # no-store + marca de fuente
            headers = [(k, v) for (k, v) in headers if k.lower() != "cache-control"]
            headers += [
                ("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0"),
                ("X-Index-Source", "bridge"),
            ]
            return _finish(start_response, status, headers, body, method)
        return inner(environ, start_response)
    return _mw
"""
    changed.append("inject _root_force_mw")

# Envolver la app una sola vez
if "app = _root_force_mw(app)" not in s:
    s = s.rstrip() + "\napp = _root_force_mw(app)\n"
    changed.append("wrap app with _root_force_mw")

# (Opcional) priorizar backend/static/index.html dentro de _serve_index_html()
m = re.search(r"^def\s+_serve_index_html\(\):\s*(?P<body>.*?)(?=^\s*def\s+\w+\(|\Z)", s, flags=re.S|re.M)
if m:
    body = m.group("body")
    body2, n = re.subn(r"(?m)^\s*candidates\s*=\s*\[(?:[^\]]+)\]",
                       '    candidates = [override] if override else [\n'
                       '        os.path.join(_REPO_DIR, "backend", "static", "index.html"),\n'
                       '        os.path.join(_REPO_DIR, "public", "index.html"),\n'
                       '        os.path.join(_REPO_DIR, "frontend", "index.html"),\n'
                       '        os.path.join(_REPO_DIR, "index.html"),\n'
                       '    ]',
                       body, count=1)
    if n:
        s = s[:m.start("body")] + body2 + s[m.end("body"):]
        changed.append("reorder index candidates")

if changed:
    P.write_text(s, encoding="utf-8")
    print("patched:", ", ".join(changed))
else:
    print("no changes")
