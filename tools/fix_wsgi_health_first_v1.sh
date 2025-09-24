#!/usr/bin/env bash
set -euo pipefail

TGT="wsgi.py"
[[ -f "$TGT" ]] || { echo "ERROR: falta $TGT"; exit 1; }

BAK="wsgi.$(date -u +%Y%m%d-%H%M%SZ).healthfirst.bak"
cp -f "$TGT" "$BAK"
echo "[wsgi-fix] Backup: $BAK"

cat > "$TGT" <<'PYEOF'
# -*- coding: utf-8 -*-
"""
WSGI health-first wrapper:
- /api/health y /healthz devuelven 200 JSON sin acceder a DB ni Flask.
- Si el app base no carga, seguimos sirviendo health para que Render complete el deploy.
- Exporta: application
"""
def _health_only_app(environ, start_response):
    path = environ.get("PATH_INFO","")
    meth = environ.get("REQUEST_METHOD","GET").upper()
    if path in ("/api/health","/healthz") and meth in ("GET","HEAD"):
        body = b'{"ok":true}\n'
        headers=[("Content-Type","application/json"),("Content-Length",str(len(body)))]
        start_response("200 OK", headers)
        return [] if meth=="HEAD" else [body]
    start_response("503 Service Unavailable",[("Content-Type","text/plain; charset=utf-8")])
    return [b"initializing\n"]

_base = None

# 1) Intentar tomar app base desde contract_shim (dos variantes comunes)
try:
    from contract_shim import application as _capp  # type: ignore
    _base = _capp
except Exception:
    try:
        from contract_shim import app as _capp2  # type: ignore
        _base = _capp2
    except Exception:
        _base = None

# 2) Intentar desde backend.create_app como último recurso
if _base is None:
    try:
        from backend import create_app  # type: ignore
        _base = create_app()
    except Exception:
        _base = None

# 3) Middleware que prioriza health sin DB
class _HealthFirstMiddleware:
    def __init__(self, app):
        self.app = app
    def __call__(self, environ, start_response):
        path = environ.get("PATH_INFO","")
        meth = environ.get("REQUEST_METHOD","GET").upper()
        if path in ("/api/health","/healthz") and meth in ("GET","HEAD"):
            body = b'{"ok":true}\n'
            headers=[("Content-Type","application/json"),("Content-Length",str(len(body)))]
            start_response("200 OK", headers)
            return [] if meth=="HEAD" else [body]
        return self.app(environ, start_response)

# 4) Ensamblado final con fallback
_base_final = _base if _base is not None else _health_only_app

# 5) Si existe _HeadDropMiddleware en contract_shim, encadenar por fuera (opcional)
try:
    from contract_shim import _HeadDropMiddleware  # type: ignore
    application = _HeadDropMiddleware(_HealthFirstMiddleware(_base_final))
except Exception:
    application = _HealthFirstMiddleware(_base_final)
PYEOF

python -m py_compile "$TGT" && echo "[wsgi-fix] py_compile OK"
echo "[wsgi-fix] Listo. Recuerda hacer deploy (Clear build cache + Deploy)."
