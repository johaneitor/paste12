import re, sys, pathlib

p = pathlib.Path("wsgiapp/__init__.py")
s = p.read_text(encoding="utf-8")

if "def _root_force_mw(" in s:
    print("ya estaba inyectado")
    sys.exit(0)

# Aseguramos 'import os' por si no está
if not re.search(r'^\s*import\s+os\b', s, flags=re.M):
    s = re.sub(r'^(import[^\n]*\n)', r'\1import os\n', s, count=1, flags=re.M)

# Función del middleware a inyectar (usa _serve_index_html y _finish ya existentes)
mw_def = r"""

# --- middleware final: fuerza '/' desde el bridge si FORCE_BRIDGE_INDEX está activo ---
def _root_force_mw(inner):
    def _mw(environ, start_response):
        path   = environ.get("PATH_INFO", "") or ""
        method = (environ.get("REQUEST_METHOD", "GET") or "GET").upper()
        _force = os.getenv("FORCE_BRIDGE_INDEX","").strip().lower() in ("1","true","yes","on")
        if _force and path in ("/","/index.html") and method in ("GET","HEAD"):
            status, headers, body = _serve_index_html()
            # Garantizar no-store y marcar fuente
            headers = [(k, v) for (k, v) in headers if k.lower() != "cache-control"]
            headers += [
                ("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0"),
                ("X-Index-Source", "bridge"),
            ]
            return _finish(start_response, status, headers, body, method)
        return inner(environ, start_response)
    return _mw
"""

# 1) Inyectamos la definición antes del final del archivo
s += mw_def

# 2) Envolvemos 'app' con el middleware. Buscamos la línea donde ya se define 'app = ...'
m = re.search(r'^\s*app\s*=\s*.+$', s, flags=re.M)
if m:
    insert_at = m.end()
    s = s[:insert_at] + "\napp = _root_force_mw(app)\n" + s[insert_at:]
else:
    # Si no encontramos, lo agregamos al final confiando en que 'app' ya existe
    s += "\napp = _root_force_mw(app)\n"

p.write_text(s, encoding="utf-8")
print("patched: inyectado _root_force_mw y aplicado sobre app")
