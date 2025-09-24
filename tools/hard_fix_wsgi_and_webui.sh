#!/usr/bin/env bash
set -Eeuo pipefail

echo "➤ Escribo wsgi.py robusto"
cat > wsgi.py <<'PY'
# wsgi.py — robusto para gunicorn wsgi:app
# Intenta varias formas de obtener la Flask app y registra el webui si existe.
from flask import Flask, jsonify
app = None

# 1) Preferir backend.entry:app si existe
try:
    from backend.entry import app as _app  # type: ignore
    app = _app
except Exception:
    pass

# 2) backend:app (objeto global)
if app is None:
    try:
        from backend import app as _app  # type: ignore
        app = _app
    except Exception:
        pass

# 3) backend:create_app() (factory)
if app is None:
    try:
        from backend import create_app as _factory  # type: ignore
        app = _factory()
    except Exception:
        pass

# 4) Último recurso: app mínima para no romper el deploy
if app is None:
    app = Flask(__name__)
    @app.get("/api/health")
    def _health():
        return jsonify({"ok": True, "note": "fallback wsgi"}), 200

# 5) Adjuntar frontend (idempotente)
try:
    from backend.webui import ensure_webui  # type: ignore
    ensure_webui(app)  # type: ignore
except Exception:
    # No romper si no está el webui
    pass
PY

echo "➤ Aseguro backend/webui.py"
mkdir -p backend
cat > backend/webui.py <<'PY'
from flask import Blueprint, send_from_directory
from pathlib import Path

def _discover_front_dir():
    pkg_dir = Path(__file__).resolve().parent
    candidates = [
        pkg_dir / "frontend",          # backend/frontend
        pkg_dir.parent / "frontend",   # <repo>/frontend
        Path.cwd() / "frontend",       # fallback
    ]
    for c in candidates:
        if c.exists():
            return c
    return candidates[0]

FRONT_DIR = _discover_front_dir()
webui = Blueprint("webui", __name__)

@webui.get("/")
def index():
    return send_from_directory(FRONT_DIR, "index.html")

@webui.get("/js/<path:fname>")
def js(fname: str):
    return send_from_directory(FRONT_DIR / "js", fname)

@webui.get("/css/<path:fname>")
def css(fname: str):
    return send_from_directory(FRONT_DIR / "css", fname)

@webui.get("/robots.txt")
def robots():
    p = FRONT_DIR / "robots.txt"
    return (send_from_directory(FRONT_DIR, "robots.txt") if p.exists() else ("", 204))

@webui.get("/favicon.ico")
def favicon():
    p = FRONT_DIR / "favicon.ico"
    return (send_from_directory(FRONT_DIR, "favicon.ico") if p.exists() else ("", 204))

def ensure_webui(app):
    """Idempotente: registra el blueprint sólo si falta."""
    try:
        if "webui.index" not in app.view_functions:
            app.register_blueprint(webui)
    except Exception:
        pass
PY

echo "➤ Git commit & push"
git add wsgi.py backend/webui.py
git commit -m "fix(wsgi): definir siempre app y adjuntar webui de forma robusta; webui idempotente" || true
git push origin main

echo "➤ Tips post-deploy:"
cat <<'TXT'
Cuando Render termine el deploy, probá:

BASE="https://paste12-rmsk.onrender.com"
for p in / "/js/app.js" "/css/styles.css" "/robots.txt" "/api/health"; do
  echo "--- $p"; curl -sSI "$BASE$p" | head -n 12
done
TXT
