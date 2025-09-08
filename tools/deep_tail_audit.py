#!/usr/bin/env python3
import re, sys, importlib, importlib.util, types, io

def scan_file():
    import pathlib
    p = pathlib.Path("wsgiapp/__init__.py")
    s = p.read_text(encoding="utf-8").replace("\r\n","\n").replace("\r","\n")
    lines = s.split("\n")
    tail = "\n".join(lines[-220:])
    print("=== Últimas ~220 líneas ===")
    print(tail)
    print("=== Heurísticas ===")
    at_root_app = [m.start() for m in re.finditer(r'(?m)^app\s*=', s)]
    print("• asignaciones 'app =' a nivel módulo:", len(at_root_app))
    cors_def = bool(re.search(r'(?m)^def\s+_root_force_mw\s*\(\s*inner\s*\)\s*:', s))
    print("• _root_force_mw definido?:", cors_def)
    cors_hook = bool(re.search(r'(?m)^app\s*=\s*_root_force_mw\(\s*app\s*\)', s))
    print("• hook CORS aplicado (app = _root_force_mw(app))?:", cors_hook)
    weird_return = bool(re.search(r'(?m)^return\s+\w+', s))
    print("• 'return ...' al nivel módulo (sospechoso):", weird_return)
    return s

def call_wsgi_app():
    # Importa wsgiapp y llama app('/api/health') en memoria
    try:
        m = importlib.import_module("wsgiapp")
        print("✓ import wsgiapp OK")
    except Exception as e:
        print("✗ import wsgiapp falló:", repr(e)); return
    if not hasattr(m, "app"):
        print("✗ wsgiapp no tiene atributo 'app'"); return
    app = getattr(m, "app")
    print("• type(app):", type(app))
    if not callable(app):
        print("✗ 'app' no es callable"); return

    status_headers = {}
    def sr(status, headers, exc_info=None):
        status_headers["status"] = status
        status_headers["headers"] = headers[:]
        return (lambda chunk: None)

    environ = {
        "REQUEST_METHOD": "GET",
        "PATH_INFO": "/api/health",
        "QUERY_STRING": "",
        "wsgi.input": io.BytesIO(b""),
    }
    try:
        body_iter = app(environ, sr)
        body = b"".join(body_iter) if hasattr(body_iter, "__iter__") else (body_iter or b"")
        print("✓ llamada WSGI /api/health ⇒", status_headers.get("status"), "bytes:", len(body))
        print("↳ headers:", status_headers.get("headers")[:5], "…")
    except Exception as e:
        print("✗ llamada WSGI falló:", repr(e))

if __name__ == "__main__":
    scan_file()
    print("\n=== Import & call ===")
    call_wsgi_app()
