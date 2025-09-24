#!/usr/bin/env bash
set -euo pipefail

# 1) Export estable en wsgiapp: define app/application con fallback a entry_main o _resolve_app()
cp -a wsgiapp/__init__.py "wsgiapp/__init__.py.bak_export_$(date -u +%Y%m%d-%H%M%SZ)"

if ! grep -q "P12 export robusto" wsgiapp/__init__.py 2>/dev/null; then
cat >> wsgiapp/__init__.py <<'PY'

# --- P12 export robusto ---
def _p12_resolve_wsgi_app():
    # Intento 1: entry_main:app
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

# Alias convencional usado por Gunicorn y otros
application = app
# --- fin P12 export robusto ---
PY
fi

python - <<'PY'
import py_compile
py_compile.compile('wsgiapp/__init__.py', doraise=True)
print("✓ py_compile wsgiapp/__init__.py OK")
PY

# 2) start_render.sh → que lance wsgiapp:application (funciona con blueprint y manual)
cat > start_render.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail
exec gunicorn wsgiapp:application \
  --chdir /opt/render/project/src \
  -w "${WEB_CONCURRENCY:-2}" -k gthread --threads "${THREADS:-4}" \
  --timeout "${TIMEOUT:-120}" -b "0.0.0.0:${PORT}"
SH
chmod +x start_render.sh

git add wsgiapp/__init__.py start_render.sh
git commit -m "ops: wsgiapp exporta app/application (fallback entry_main/_resolve_app) + start → wsgiapp:application"
