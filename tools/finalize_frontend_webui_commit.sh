#!/usr/bin/env bash
set -Eeuo pipefail

mkdir -p backend/frontend/js backend/frontend/css

# 1) Sincronizar frontend al árbol backend/
[ -f frontend/index.html ] && cp -f frontend/index.html backend/frontend/index.html
[ -f frontend/js/app.js ] && cp -f frontend/js/app.js backend/frontend/js/app.js
[ -f frontend/css/styles.css ] && cp -f frontend/css/styles.css backend/frontend/css/styles.css
[ -f frontend/robots.txt ] && cp -f frontend/robots.txt backend/frontend/robots.txt
[ -f frontend/terms.html ] && cp -f frontend/terms.html backend/frontend/terms.html
[ -f frontend/privacy.html ] && cp -f frontend/privacy.html backend/frontend/privacy.html
[ -f frontend/favicon.ico ] && cp -f frontend/favicon.ico backend/frontend/favicon.ico

# 2) Reescribir webui.py con autodetección del FRONT_DIR que tenga index.html
python - <<'PY'
from pathlib import Path
code = '''from flask import Blueprint, send_from_directory
from pathlib import Path

PKG_DIR = Path(__file__).resolve().parent
CANDIDATES = [
    PKG_DIR / "frontend",          # backend/frontend
    PKG_DIR.parent / "frontend",   # <repo>/frontend
    Path.cwd() / "frontend",       # fallback
]
FRONT_DIR = None
for c in CANDIDATES:
    if (c / "index.html").exists():
        FRONT_DIR = c
        break
if FRONT_DIR is None:
    FRONT_DIR = CANDIDATES[0]

webui = Blueprint("webui", __name__)

@webui.route("/", methods=["GET", "HEAD"])
def index():
    return send_from_directory(FRONT_DIR, "index.html")

@webui.route("/js/<path:fname>", methods=["GET", "HEAD"])
def js(fname):
    return send_from_directory(FRONT_DIR / "js", fname)

@webui.route("/css/<path:fname>", methods=["GET", "HEAD"])
def css(fname):
    return send_from_directory(FRONT_DIR / "css", fname)

@webui.route("/favicon.ico", methods=["GET", "HEAD"])
def favicon():
    p = FRONT_DIR / "favicon.ico"
    if p.exists():
        return send_from_directory(FRONT_DIR, "favicon.ico")
    return ("", 204)

@webui.route("/robots.txt", methods=["GET", "HEAD"])
def robots():
    p = FRONT_DIR / "robots.txt"
    if p.exists():
        return send_from_directory(FRONT_DIR, "robots.txt")
    return ("", 204)

@webui.route("/terms.html", methods=["GET", "HEAD"])
def terms():
    p = FRONT_DIR / "terms.html"
    if p.exists():
        return send_from_directory(FRONT_DIR, "terms.html")
    return ("", 404)

@webui.route("/privacy.html", methods=["GET", "HEAD"])
def privacy():
    p = FRONT_DIR / "privacy.html"
    if p.exists():
        return send_from_directory(FRONT_DIR, "privacy.html")
    return ("", 404)
'''
p = Path("backend/webui.py")
p.write_text(code, encoding="utf-8")
print("webui.py OK")
PY

# 3) Inyectar registro del blueprint en backend/__init__.py para ambos modos
python - <<'PY'
from pathlib import Path
import re, inspect

initp = Path("backend/__init__.py")
s = initp.read_text(encoding="utf-8")

block = '''
# === Ensure web UI blueprint is registered (global app & factory) ===
try:
    from .webui import webui as _webui
    # Registrar en app global si existe (backend:app)
    if "app" in globals() and hasattr(globals()["app"], "register_blueprint"):
        try:
            globals()["app"].register_blueprint(_webui)
        except Exception:
            pass
    # Envolver factory si existe (backend:create_app)
    if "create_app" in globals() and callable(create_app):
        try:
            _src = inspect.getsource(create_app)
        except Exception:
            _src = ""
        if "register_blueprint(_webui)" not in _src and "register_blueprint(webui)" not in _src:
            _orig_create_app = create_app
            def create_app(*a, **kw):
                app = _orig_create_app(*a, **kw)
                try:
                    from .webui import webui as _w
                    app.register_blueprint(_w)
                except Exception:
                    pass
                return app
except Exception:
    # No romper el API si falta frontend
    pass
'''

if "Ensure web UI blueprint is registered" not in s:
    if not s.endswith("\n"):
        s += "\n"
    s += block + "\n"
    initp.write_text(s, encoding="utf-8")
    print("__init__.py: bloque de registro agregado.")
else:
    print("__init__.py: bloque ya presente (ok).")
PY

git add backend/webui.py backend/frontend/index.html backend/frontend/js/app.js backend/frontend/css/styles.css backend/frontend/robots.txt backend/frontend/terms.html backend/frontend/privacy.html backend/frontend/favicon.ico backend/__init__.py || true
git commit -m "fix(web): servir frontend y registrar blueprint en app global y factory (compat Render); copiar index/js/css a backend/frontend" || true
git push origin main
