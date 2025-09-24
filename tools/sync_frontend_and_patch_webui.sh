#!/usr/bin/env bash
set -Eeuo pipefail

mkdir -p backend/frontend/js backend/frontend/css

# Copiar assets principales al árbol backend/ (Render-friendly)
cp -f frontend/index.html              backend/frontend/index.html
cp -f frontend/js/app.js              backend/frontend/js/app.js
[ -f frontend/css/styles.css ] && cp -f frontend/css/styles.css backend/frontend/css/styles.css

# Reescribir webui.py con selección de FRONT_DIR que tenga index.html y ruta /css
python - <<'PY'
from pathlib import Path
p = Path("backend/webui.py")
code = '''from flask import Blueprint, send_from_directory
from pathlib import Path

PKG_DIR = Path(__file__).resolve().parent
CANDIDATES = [
    PKG_DIR / "frontend",          # backend/frontend
    PKG_DIR.parent / "frontend",   # <repo>/frontend
    Path.cwd() / "frontend",
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
p.write_text(code, encoding="utf-8")
print("webui.py reescrito con ruta /css y selección de FRONT_DIR con index.html.")
PY

git add backend/webui.py backend/frontend/index.html backend/frontend/js/app.js backend/frontend/css/styles.css || true
git commit -m "fix(web): mover index/js/css a backend/frontend y servir /css; elegir FRONT_DIR que tenga index.html" || true
git push origin main
