#!/usr/bin/env bash
set -euo pipefail

tgt="contract_shim.py"
[[ -f "$tgt" ]] || { echo "ERROR: falta $tgt"; exit 1; }

bak="contract_shim.$(date -u +%Y%m%d-%H%M%SZ).health.bak"
cp -f "$tgt" "$bak"
echo "[health-bypass] Backup: $bak"

python - <<'PY'
import io, re
p="contract_shim.py"
s=io.open(p,"r",encoding="utf-8").read()
orig=s

# 1) Definición del middleware (idempotente)
if "class _HealthBypassMiddleware" not in s:
    s += r"""

# == Health bypass (no DB, no framework) ==
class _HealthBypassMiddleware:
    def __init__(self, app):
        self.app = app
    def __call__(self, environ, start_response):
        path  = environ.get('PATH_INFO','')
        meth  = environ.get('REQUEST_METHOD','GET').upper()
        if path in ('/api/health','/healthz') and meth in ('GET','HEAD'):
            body = b'{"ok":true}\n'
            headers=[('Content-Type','application/json'),
                     ('Content-Length', str(len(body)))]
            start_response('200 OK', headers)
            return [] if meth=='HEAD' else [body]
        return self.app(environ, start_response)
"""

# 2) Unificar encadenado de middlewares de forma segura:
#    - Tomamos application si existe; si no, app.
#    - Encapsulamos con HealthBypass y, si existe, mantenemos el HeadDrop por fuera.
lines = []
wrapped = False
for ln in s.splitlines(True):
    lines.append(ln)

s2 = "".join(lines)

# Construye bloque final único que define 'application' con el orden correcto:
# outer: _HeadDropMiddleware (si existe)
# inner: _HealthBypassMiddleware
tail_block = r"""
# === Paste12: unify WSGI wrappers (idempotent) ===
try:
    _p12_base_app = application
except NameError:
    try:
        _p12_base_app = app
    except NameError:
        _p12_base_app = None

if _p12_base_app is not None:
    # Siempre aplicar HealthBypass por dentro
    _p12_wrapped = _HealthBypassMiddleware(_p12_base_app)
    # Si existe HeadDrop, volver a envolver por fuera; si no, usar el envuelto base
    try:
        _ = _HeadDropMiddleware
        application = _HeadDropMiddleware(_p12_wrapped)
    except NameError:
        application = _p12_wrapped
"""

if "Paste12: unify WSGI wrappers" not in s2:
    s2 += "\n" + tail_block + "\n"

if s2 != orig:
    io.open(p,"w",encoding="utf-8").write(s2)
    print("[health-bypass] aplicado OK")
else:
    print("[health-bypass] ya estaba OK")
PY

python -m py_compile contract_shim.py && echo "py_compile OK"
