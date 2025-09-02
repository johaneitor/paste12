import re, sys, pathlib
p = pathlib.Path("wsgiapp/__init__.py")
s = p.read_text(encoding="utf-8")

# Insertar inmediatamente después de "def _app(environ, start_response):"
pat = r"(def\s+_middleware\s*\(\s*inner_app.*?is_fallback.*?\):\s*\n\s*def\s+_app\s*\(\s*environ,\s*start_response\s*\):\s*\n)"
inject = r"""\1        # --- HARD FORCE ROOT INDEX FROM BRIDGE ---
        _force = os.getenv("FORCE_BRIDGE_INDEX","").strip().lower() in ("1","true","yes","on")
        if _force:
            _p = environ.get("PATH_INFO","")
            _m = environ.get("REQUEST_METHOD","GET").upper()
            if _p in ("/", "/index.html") and _m in ("GET","HEAD"):
                status, headers, body = _serve_index_html()
                # asegurar no-store y marcar fuente
                headers = [(k,v) for (k,v) in headers if k.lower()!="cache-control"]
                headers += [("Cache-Control","no-store, no-cache, must-revalidate, max-age=0"),
                            ("X-Index-Source","bridge")]
                return _finish(start_response, status, headers, body, _m)
"""

ns, n = re.subn(pat, inject, s, flags=re.S)
if n == 0:
    print("No se pudo inyectar (¿ya estaba parcheado o cambió la firma?)", file=sys.stderr)
    sys.exit(1)
p.write_text(ns, encoding="utf-8")
print("patched: intercept '/' al inicio de _app cuando FORCE_BRIDGE_INDEX=1")
