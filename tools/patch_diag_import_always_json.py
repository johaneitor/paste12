#!/usr/bin/env python3
import re, sys, json, os, pathlib
p = pathlib.Path("wsgiapp/__init__.py")
s = p.read_text(encoding="utf-8", errors="ignore")

# Intento minimalista: si existe helper _finish úsalo; si no, devolvé WSGI puro.
has_finish = "_finish(" in s

snippet = r'''
def _diag_import_app(environ, start_response):
    try:
        import os, json
        # Redacta valores sensibles
        def redact(k,v):
            SK = ('KEY','SECRET','TOKEN','PASS','PWD','PASSWORD','DATABASE_URL','DB_')
            if any(x in k.upper() for x in SK): return '***redacted***'
            return v
        env = {k: redact(k,v) for k,v in os.environ.items()}
        body = json.dumps({"ok": True, "env": env}, ensure_ascii=False).encode("utf-8")
        headers = [("Content-Type","application/json; charset=utf-8")]
    except Exception as e:
        body = json.dumps({"ok": False, "error": str(e)}, ensure_ascii=False).encode("utf-8")
        headers = [("Content-Type","application/json; charset=utf-8")]

    # Respuesta
    %RETURN%
'''

route_rx = re.compile(r'(?ms)def\s+app\s*\(environ,\s*start_response\)\s*:\s*\n')
m = route_rx.search(s)
if not m:
    print("No encontré app(environ,start_response); aborto.")
    sys.exit(1)

return_line = ("return _finish(start_response, '200 OK', headers, body)"
               if has_finish else
               "start_response('200 OK', headers)\n    return [body]")

snip = snippet.replace("%RETURN%", return_line)

# Inyecta handler y ruta muy específica
if "/diag/import" in s:
    s = re.sub(r'(?ms)(/diag/import.+?)$', r'\1', s)  # noop, ya existe path; no tocamos esa línea
# Insertamos un matcher antes del resto de rutas (compat con router manual)
router_patch = r'''
    # --- diag import (always JSON, redacted) ---
    path = (environ.get('PATH_INFO') or '').strip()
    if path == '/diag/import':
        return _diag_import_app(environ, start_response)
'''

s = route_rx.sub(lambda m: s[:m.end()] + router_patch + s[m.end():], s)
# Agrega el helper si no existe
if "_diag_import_app(" not in s:
    s = s + "\n\n" + snip

p.write_text(s, encoding="utf-8")
print("OK: parche diag/import aplicado.")
