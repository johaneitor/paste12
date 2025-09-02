import re, sys, pathlib, json
p = pathlib.Path("wsgiapp/__init__.py")
s = p.read_text(encoding="utf-8")

# Localizar el inicio del _middleware y del _app:
m = re.search(r"def\s+_middleware\s*\(\s*inner_app.*?,\s*is_fallback.*?\):\s*\n\s*def\s+_app\s*\(\s*environ,\s*start_response\s*\):", s)
if not m:
    print("no encontré _middleware/_app (anchor)")
    sys.exit(1)

# Luego de obtener path/method(/qs), inyectamos el handler forzado
anchor = re.search(
    r"""
    (               # grupo 1 = bloque donde ya se extraen path/method(/qs)
      \n\s*path\s*=\s*environ\.get\("PATH_INFO".*?\)\s*\n
      \s*method\s*=\s*environ\.get\("REQUEST_METHOD".*?\)\.upper\(\)\s*\n
      (?:\s*qs\s*=\s*environ\.get\("QUERY_STRING".*?\)\s*\n)?
    )
    """,
    s[m.start():], flags=re.S|re.X
)
if not anchor:
    print("no encontré el bloque de path/method(/qs)")
    sys.exit(1)

inject = r"""
        # --- FORCE_BRIDGE_INDEX: servir index pastel en "/" aún si no estamos en fallback ---
        _force = os.getenv("FORCE_BRIDGE_INDEX","").strip().lower() in ("1","true","yes","on")
        if (_force or is_fallback) and path in ("/", "/index.html") and method in ("GET","HEAD"):
            status, headers, body = _serve_index_html()
            # Asegurar no-store y marcar la fuente para debug
            headers = [(k,v) for (k,v) in headers if k.lower()!="cache-control"] + [
                ("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0"),
                ("X-Index-Source", "bridge")
            ]
            return _finish(start_response, status, headers, body, method)
"""

start = m.start() + anchor.start(1)
end   = m.start() + anchor.end(1)
ns = s[:end] + inject + s[end:]
if ns == s:
    print("no se aplicó cambio")
    sys.exit(1)

p.write_text(ns, encoding="utf-8")
print("patched: root '/' ahora lo sirve el bridge cuando FORCE_BRIDGE_INDEX=1 y añade no-store")
