#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile
W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists(): print("✗ no existe wsgiapp/__init__.py"); sys.exit(2)
src = W.read_text(encoding="utf-8").replace("\r\n","\n").replace("\r","\n")

# ¿Ya está el wrapper?
if re.search(r'(?m)^\s*def\s+_root_force_mw\s*\(\s*inner\s*\)\s*:\s*$', src):
    print("OK: _root_force_mw ya existe"); sys.exit(0)

BLOCK = r'''
def _root_force_mw(inner):
    # Envuelve la app para inyectar CORS en TODAS las respuestas cuando hay Origin
    def _mw(environ, start_response):
        origin = environ.get("HTTP_ORIGIN")
        # interceptamos la respuesta para poder ajustar headers
        status_holder = {"status": "200 OK"}
        headers_holder = {"headers": []}
        def sr(status, headers, exc_info=None):
            status_holder["status"] = status
            headers_holder["headers"] = list(headers)
            # wsgi exige devolver un write(); pero no lo usamos
            return (lambda data: None)
        body_iter = inner(environ, sr)
        body = b"".join(body_iter) if hasattr(body_iter, "__iter__") else (body_iter or b"")
        headers = headers_holder["headers"]

        # remueve Content-Length para no romper si cambiamos headers
        headers = [(k, v) for (k, v) in headers if k.lower() != "content-length"]

        if origin:
            # upsert helpers
            low = {k.lower(): i for i, (k, _) in enumerate(headers)}
            def upsert(k, v):
                i = low.get(k.lower())
                if i is None:
                    headers.append((k, v))
                    low[k.lower()] = len(headers) - 1
                else:
                    k0, _ = headers[i]; headers[i] = (k0, v)
            upsert("Access-Control-Allow-Origin", origin)  # eco del origin
            upsert("Vary", "Origin")
            upsert("Access-Control-Allow-Credentials", "true")
            upsert("Access-Control-Expose-Headers", "Link, X-Next-Cursor, X-Summary-Applied, X-Summary-Limit")

        start_response(status_holder["status"], headers)
        return [body]
    return _mw
'''

# Insertamos el bloque antes de la zona donde se aplica el hook (si existe),
# o justo antes de la asignación a 'app = _middleware('.
ins = re.search(r'(?m)^\s*app\s*=\s*_middleware\(', src)
insert_pos = ins.start() if ins else len(src)

new_src = src[:insert_pos] + "\n" + BLOCK.strip() + "\n" + src[insert_pos:]
bak = W.with_suffix(".py.add_cors_wrapper_mw.bak")
if not bak.exists(): shutil.copyfile(W, bak)
W.write_text(new_src, encoding="utf-8")
print(f"patched: _root_force_mw añadido | backup={bak.name}")

# Aseguramos el hook (app = _root_force_mw(app)) si no está
src2 = W.read_text(encoding="utf-8")
if not re.search(r'(?m)^\s*app\s*=\s*_root_force_mw\(\s*app\s*\)\s*$', src2):
    src2 = re.sub(
        r'(?m)^(?P<ind>\s*)app\s*=\s*_middleware\([^\n]+\)\s*$',
        r'\g<ind>app = _middleware(_app, is_fallback=(_app is None))\n\g<ind>try:\n\g<ind>    app = _root_force_mw(app)\n\g<ind>except Exception:\n\g<ind>    pass',
        src2, count=1
    )
    W.write_text(src2, encoding="utf-8")
    print("hook: app = _root_force_mw(app) aplicado")

py_compile.compile(str(W), doraise=True)
print("✓ py_compile OK")
