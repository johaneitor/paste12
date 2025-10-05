#!/usr/bin/env bash
set -euo pipefail

# Backup
cp -f wsgi.py "wsgi.py.bak-$(date -u +%Y%m%d-%H%M%SZ)" 2>/dev/null || true

cat > wsgi.py << 'PY'
# wsgi.py — WSGI mínimo y seguro (sin regex)
import os, json, time

try:
    # Importa la app base (Flask) desde wsgiapp
    from wsgiapp import application as _base_app
except Exception as e:
    # Fallback a app vacía si algo falla (evita crash del proceso)
    def _base_app(environ, start_response):
        body = b'{"ok":false,"error":"base_app_import"}'
        start_response("500 Internal Server Error",
                       [("Content-Type","application/json"),
                        ("Content-Length", str(len(body)))])
        return [body]

def _deploy_stamp(environ, start_response):
    commit = (os.environ.get("RENDER_GIT_COMMIT")
              or os.environ.get("SOURCE_COMMIT")
              or os.environ.get("GIT_COMMIT")
              or os.environ.get("COMMIT_SHA")
              or "unknown")
    body = json.dumps({
        "commit": commit,
        "date": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    }).encode("utf-8")
    start_response("200 OK", [
        ("Content-Type","application/json"),
        ("Cache-Control","no-store"),
        ("Content-Length", str(len(body)))
    ])
    return [body]

def _index(environ, start_response):
    # Sirve un index estático si existe; si no, uno mínimo
    paths = ("index.html","static/index.html","public/index.html")
    data = None
    for p in paths:
        try:
            with open(p, "rb") as f:
                data = f.read()
                break
        except Exception:
            pass
    if not data:
        data = b"<!doctype html><meta name='p12-commit' content='unknown'><body data-single='1'>paste12</body>"
    # Cache bust para evitar SW/Cloudflare viejos
    start_response("200 OK", [
        ("Content-Type","text/html; charset=utf-8"),
        ("Cache-Control","no-store, max-age=0"),
        ("Content-Length", str(len(data)))
    ])
    return [data]

# Dispatcher final
def application(environ, start_response):
    path = environ.get("PATH_INFO","/") or "/"
    if path == "/api/deploy-stamp":
        return _deploy_stamp(environ, start_response)
    if path in ("/", "/index.html"):
        return _index(environ, start_response)
    return _base_app(environ, start_response)
PY

python -m py_compile wsgi.py
echo "PATCH_OK wsgi.py"
