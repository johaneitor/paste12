#!/usr/bin/env bash
set -euo pipefail
TS="$(date -u +%Y%m%d-%H%M%SZ)"
[[ -f contract_shim.py ]] && cp -f contract_shim.py "contract_shim.py.${TS}.bak" || true
echo "[shim] Backup: contract_shim.py.${TS}.bak"

cat > contract_shim.py <<'PY'
# contract_shim: front-lock serving + backend passthrough
import os, json, importlib

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
FRONT_DIR = os.path.join(BASE_DIR, 'frontend')
INDEX = os.path.join(FRONT_DIR, 'index.html')
PRIV  = os.path.join(FRONT_DIR, 'privacy.html')
TERMS = os.path.join(FRONT_DIR, 'terms.html')

def _load_real_app():
    tried = []
    # intentamos app directa o factory
    candidates = [
        ('backend.app','app'),
        ('backend','create_app'),
        ('backend.main','app'),
        ('backend.wsgi','app'),
    ]
    for mod, attr in candidates:
        try:
            m = importlib.import_module(mod)
            app = getattr(m, attr)
            if callable(app):  # factory
                app = app()
            return app, None
        except Exception as e:
            tried.append(f"{mod}:{attr} -> {e.__class__.__name__}: {e}")
    return None, "; ".join(tried)

REAL_APP, DIAG = _load_real_app()

def _serve_static(path, start_response, status='200 OK'):
    if not os.path.exists(path):
        start_response('404 Not Found', [('Content-Type','text/plain; charset=utf-8')])
        return [b'not found']
    with open(path, 'rb') as f:
        data = f.read()
    headers = [
        ('Content-Type','text/html; charset=utf-8'),
        ('Cache-Control','no-store, max-age=0'),
        ('X-Served-By','contract_shim.front'),
    ]
    start_response(status, headers)
    return [data]

def _health(environ, start_response):
    body = json.dumps({'ok': True, 'api': REAL_APP is not None, 'ver': 'factory+frontlock'})
    start_response('200 OK', [('Content-Type','application/json')])
    return [body.encode('utf-8')]

def application(environ, start_response):
    path = environ.get('PATH_INFO') or '/'
    method = (environ.get('REQUEST_METHOD') or 'GET').upper()

    # Bloqueo de frontend: servimos los HTML del repo SIN modificación.
    if method in ('GET','HEAD'):
        if path == '/':
            return _serve_static(INDEX, start_response)
        if path == '/privacy':
            return _serve_static(PRIV, start_response)
        if path == '/terms':
            return _serve_static(TERMS, start_response)
        if path == '/api/health':
            return _health(environ, start_response)

    # Resto pasa al backend real
    if REAL_APP is None:
        start_response('500 Internal Server Error', [('Content-Type','text/plain; charset=utf-8')])
        return [f"Shim can't import app: {DIAG}".encode('utf-8')]
    return REAL_APP.wsgi_app(environ, start_response)
PY

python -m py_compile contract_shim.py && echo "[shim] py_compile OK"
echo "[shim] listo"
