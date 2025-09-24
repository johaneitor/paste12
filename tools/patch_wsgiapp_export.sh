#!/usr/bin/env bash
set -euo pipefail

# Backup
cp -a wsgiapp/__init__.py "wsgiapp/__init__.py.bak_export_$(date -u +%Y%m%d-%H%M%SZ)"

# Append de alias/export robusto (NO aplasta helpers ni _finish)
cat >> wsgiapp/__init__.py <<'PY'

# --- P12: export robusto de WSGI app (tolerante a start antiguo o blueprint) ---
# Objetivo: garantizar que 'wsgiapp:app' y 'wsgiapp:application' EXISTAN y sean WSGI callables.
# 1) Si entry_main:app existe, úsalo.  2) Si no, probá con _resolve_app() legacy.  3) Si nada, 500 claro.

def _p12_resolve_wsgi_app():
    # Intento 1: entry_main:app (si está presente)
    try:
        from entry_main import app as entry_app
        if callable(entry_app):
            return entry_app
    except Exception:
        pass
    # Intento 2: resolver interno legacy (si existe)
    try:
        if '_resolve_app' in globals() and callable(_resolve_app):
            candidate = _resolve_app()
            if candidate:
                return candidate
    except Exception:
        pass
    return None

def app(environ, start_response):
    target = _p12_resolve_wsgi_app()
    if target is None:
        start_response('500 Internal Server Error', [('Content-Type','text/plain; charset=utf-8')])
        return [b'wsgiapp: no pude resolver la WSGI app (entry_main o _resolve_app)']
    return target(environ, start_response)

# Alias gunicorn convencional
application = app
# --- fin P12 export robusto ---
PY

# Validar sintaxis Python antes de commitear
python - <<'PY'
import py_compile
py_compile.compile('wsgiapp/__init__.py', doraise=True)
print("✓ py_compile wsgiapp/__init__.py OK")
PY

git add wsgiapp/__init__.py
git commit -m "ops: export WSGI estable en wsgiapp (app/application) con fallback a entry_main o _resolve_app"
