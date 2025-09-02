import re, pathlib

P = pathlib.Path("wsgiapp/__init__.py")
s = P.read_text(encoding="utf-8")
changed = False

# 0) asegurar import os
if not re.search(r'^\s*import\s+os\b', s, flags=re.M):
    s = re.sub(r'^(import[^\n]*\n)', r'\1import os\n', s, count=1, flags=re.M)
    changed = True

# 1) inyectar clase wrapper si no está
if "class _ForceRootIndexWrapper" not in s:
    s += r"""

class _ForceRootIndexWrapper:
    def __init__(self, inner):
        self.inner = inner
    def __call__(self, environ, start_response):
        try:
            force = os.getenv("FORCE_BRIDGE_INDEX","").strip().lower() in ("1","true","yes","on")
        except Exception:
            force = False
        if force:
            path = (environ.get("PATH_INFO","") or "")
            method = (environ.get("REQUEST_METHOD","GET") or "GET").upper()
            if path in ("/","/index.html") and method in ("GET","HEAD"):
                status, headers, body = _serve_index_html()
                # Garantizar no-store y marcar fuente
                headers = [(k,v) for (k,v) in headers if k.lower()!="cache-control"]
                headers += [
                    ("Cache-Control","no-store, no-cache, must-revalidate, max-age=0"),
                    ("X-Index-Source","bridge"),
                ]
                return _finish(start_response, status, headers, body, method)
        return self.inner(environ, start_response)
"""
    changed = True

# 2) envolver la app final (una sola vez)
if "FORCE_ROOT_WRAPPED = True" not in s:
    # buscamos la última definición de 'app =' y agregamos el wrapper al final del archivo
    s += r"""

# --- forzar raíz desde bridge cuando se habilita FORCE_BRIDGE_INDEX ---
app = _ForceRootIndexWrapper(app)
FORCE_ROOT_WRAPPED = True
"""
    changed = True

if changed:
    P.write_text(s, encoding="utf-8")
    print("patched: root wrapper añadido y aplicado")
else:
    print("no changes")
