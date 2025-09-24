#!/usr/bin/env bash
set -euo pipefail

TGT="wsgi.py"
[[ -f "$TGT" ]] || { echo "ERROR: falta $TGT"; exit 1; }

BAK="wsgi.$(date -u +%Y%m%d-%H%M%SZ).lazyhealth.bak"
cp -f "$TGT" "$BAK"
echo "[wsgi-fix] Backup: $BAK"

cat > "$TGT" <<'PYEOF'
# -*- coding: utf-8 -*-
"""
WSGI 'lazy + health-first':
- /api/health y /healthz devuelven 200 JSON sin tocar DB o Flask.
- El app real se importa y monta *perezosamente* en el primer request NO-health.
- Exporta: application  (WSGI callable)
"""
import sys

def _health(environ, start_response):
    path = environ.get("PATH_INFO","")
    meth = environ.get("REQUEST_METHOD","GET").upper()
    if path in ("/api/health","/healthz") and meth in ("GET","HEAD"):
        body = b'{"ok":true,"api":true,"ver":"wsgi-lazy-v2"}\n'
        headers=[("Content-Type","application/json"),("Content-Length",str(len(body)))]
        start_response("200 OK", headers)
        return [] if meth=="HEAD" else [body]
    return None  # no es health

class _LazyDispatch:
    __slots__ = ("_app","_tried")
    def __init__(self):
        self._app = None
        self._tried = False

    def _resolve_app(self):
        if self._tried:
            return
        self._tried = True
        # 1) contract_shim.application (si existe)
        try:
            from contract_shim import application as capp  # type: ignore
            self._app = capp
            sys.stderr.write("[wsgi-lazy] mounted contract_shim.application\n")
            return
        except Exception as e:
            sys.stderr.write(f"[wsgi-lazy] contract_shim.application fail: {e}\n")
        # 2) contract_shim.app (algunos repos exportan 'app')
        try:
            from contract_shim import app as capp2  # type: ignore
            self._app = capp2
            sys.stderr.write("[wsgi-lazy] mounted contract_shim.app\n")
            return
        except Exception as e:
            sys.stderr.write(f"[wsgi-lazy] contract_shim.app fail: {e}\n")
        # 3) backend.create_app()
        try:
            from backend import create_app  # type: ignore
            self._app = create_app()
            sys.stderr.write("[wsgi-lazy] mounted backend.create_app()\n")
            return
        except Exception as e:
            sys.stderr.write(f"[wsgi-lazy] backend.create_app fail: {e}\n")

    def __call__(self, environ, start_response):
        # Atender health *antes* de cualquier import/carga
        h = _health(environ, start_response)
        if h is not None:
            return h

        if self._app is None:
            self._resolve_app()

        if self._app is None:
            # App aún no disponible (por ejemplo, problemas de DB): no romper deploy
            msg = b'{"ok":false,"reason":"app-not-ready"}\n'
            start_response("503 Service Unavailable", [("Content-Type","application/json"),
                                                       ("Content-Length", str(len(msg)))])
            return [msg]

        return self._app(environ, start_response)

# WSGI callable
application = _LazyDispatch()
PYEOF

python -m py_compile "$TGT" && echo "[wsgi-fix] py_compile OK"
echo "[wsgi-fix] Listo. Recuerda: en Render usa Start Command:"
echo "  gunicorn wsgi:application --chdir /opt/render/project/src -w \${WEB_CONCURRENCY:-2} -k gthread --threads \${THREADS:-4} --timeout \${TIMEOUT:-120} -b 0.0.0.0:\$PORT"
