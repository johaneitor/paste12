import re, sys, pathlib
p = pathlib.Path("wsgiapp/__init__.py")
s = p.read_text(encoding="utf-8")

# Encontrar la función _middleware(...): def _middleware(inner_app:..., is_fallback:...):
mm = re.search(r"def\s+_middleware\s*\(\s*inner_app.*?\):\s*\n\s*def\s+_app\s*\(\s*environ,\s*start_response\s*\):", s)
if not mm:
    print("no encontré _middleware/_app")
    sys.exit(1)

# Después de obtener path/method/qs añadimos el interceptor forzado
anchor_pat = r"""(\n\s*path\s*=\s*environ\.get\("PATH_INFO".*?\)\s*\n\s*method\s*=\s*environ\.get\("REQUEST_METHOD".*?\)\.upper\(\)\s*\n(?:\s*qs\s*=\s*environ\.get\("QUERY_STRING".*?\)\s*\n)?)"""
inject = r"""
        # --- FORCE_BRIDGE_INDEX: servir index pastel en "/" aún si no estamos en fallback ---
        _force = os.getenv("FORCE_BRIDGE_INDEX","").strip().lower() in ("1","true","yes","on")
        if (_force or is_fallback) and path in ("/", "/index.html") and method in ("GET","HEAD"):
            status, headers, body = _serve_index_html()
            # Asegurar no-store e impedir que otro cache lo reemplace
            headers = [(k,v) for (k,v) in headers if k.lower()!="cache-control"] + [
                ("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
            ]
            return _finish(start_response, status, headers, body, method)
"""

ns, n = re.subn(anchor_pat, r"\1"+inject, s, flags=re.S)
if n:
    p.write_text(ns, encoding="utf-8")
    print("patched: FORCE_BRIDGE_INDEX root handler + no-store")
else:
    print("ya estaba parcheado o no se encontró el anchor (path/method/qs)")
