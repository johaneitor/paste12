#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ no existe wsgiapp/__init__.py"); sys.exit(2)

src = W.read_text(encoding="utf-8").replace("\r\n","\n").replace("\r","\n")

# Ya existe una definición funcional?
if re.search(r'^\s*def\s+_root_force_mw\s*\(\s*inner\s*\)\s*:\s*\n(?!\s*pass\b)', src, re.M):
    print("OK: _root_force_mw ya definido (no se cambia)"); sys.exit(0)

# Plantilla segura (_root_force_mw define CORS handler para /api/* y OPTIONS)
BLOCK = r'''
def _root_force_mw(inner):
    # Middleware raíz: CORS + OPTIONS para /api/*
    def _mw(environ, start_response):
        path   = (environ.get("PATH_INFO") or "")
        method = (environ.get("REQUEST_METHOD") or "GET").upper()
        origin = environ.get("HTTP_ORIGIN")

        def _cors_headers(headers):
            # Inserta CORS sólo si viene Origin
            if not origin:
                return headers
            low = {k.lower(): i for i,(k,_) in enumerate(headers)}
            def upsert(k, v):
                i = low.get(k.lower())
                if i is None:
                    headers.append((k, v))
                    low[k.lower()] = len(headers)-1
                else:
                    k0,_ = headers[i]; headers[i] = (k0, v)
            upsert("Access-Control-Allow-Origin", origin)
            upsert("Vary", "Origin")
            upsert("Access-Control-Allow-Credentials", "true")
            upsert("Access-Control-Expose-Headers", "Link, X-Next-Cursor, X-Summary-Applied, X-Summary-Limit")
            return headers

        if method == "OPTIONS" and path.startswith("/api/"):
            # Respuesta preflight mínima
            hdrs = [
                ("Content-Type", "application/json; charset=utf-8"),
                ("Access-Control-Allow-Methods", "GET,POST,OPTIONS"),
                ("Access-Control-Allow-Headers", "Content-Type, Accept"),
                ("Access-Control-Max-Age", "600"),
            ]
            hdrs = _cors_headers(hdrs)
            start_response("204 No Content", hdrs)
            return [b""]

        # Normal: inyecta CORS en la respuesta saliente si aplica
        st = {"status": "200 OK", "headers": []}
        def sr(status, headers, exc_info=None):
            st["status"] = status; st["headers"] = list(headers)
            return (lambda data: None)
        body_iter = inner(environ, sr)
        body = b"".join(body_iter) if hasattr(body_iter, "__iter__") else (body_iter or b"")
        headers = _cors_headers(st["headers"])
        # Evitar Content-Length incorrecto
        headers = [(k,v) for (k,v) in headers if k.lower() != "content-length"]
        start_response(st["status"], headers)
        return [body]
    return _mw
'''

# Inserta la definición antes del hook donde se aplica
# Buscar el punto del hook:
hook = re.search(r'\n\s*try:\s*\n\s*_root_force_mw\s*#.*?\n', src)
if hook:
    insert_pos = hook.start()
else:
    # fallback: antes de la primera asignación "app  = _middleware("
    m2 = re.search(r'\n\s*app\s*=\s*_middleware\(', src)
    insert_pos = m2.start() if m2 else len(src)

new_src = src[:insert_pos] + "\n" + BLOCK.strip() + "\n" + src[insert_pos:]

bak = W.with_suffix(".py.patch_cors_mw.bak")
if not bak.exists():
    shutil.copyfile(W, bak)
W.write_text(new_src, encoding="utf-8")
print(f"patched: _root_force_mw(CORS/OPTIONS) inyectado | backup={bak.name}")

# Gate de compilación
py_compile.compile(str(W), doraise=True)
print("✓ py_compile OK")
