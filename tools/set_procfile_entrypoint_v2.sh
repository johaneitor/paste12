#!/usr/bin/env bash
set -Eeuo pipefail

TMPROOT="${TMPDIR:-/data/data/com.termux/files/usr/tmp}"
PIDFILE="$TMPROOT/p12_guni.pid"
mkdir -p "$TMPROOT"

echo "➤ Escribo backend/webui.py (blueprint robusto)"
mkdir -p backend
cat > backend/webui.py <<'PY'
from flask import Blueprint, send_from_directory
from pathlib import Path

PKG_DIR = Path(__file__).resolve().parent
CANDIDATES = [
    PKG_DIR / 'frontend',          # backend/frontend  (deploy donde backend es root)
    PKG_DIR.parent / 'frontend',   # <repo>/frontend   (deploy repo root)
    Path.cwd() / 'frontend',       # fallback
]
for c in CANDIDATES:
    if c.exists():
        FRONT_DIR = c
        break
else:
    FRONT_DIR = CANDIDATES[0]

webui = Blueprint('webui', __name__)

@webui.route('/', methods=['GET'])
def index():
    return send_from_directory(FRONT_DIR, 'index.html')

@webui.route('/js/<path:fname>', methods=['GET'])
def js(fname):
    return send_from_directory(FRONT_DIR / 'js', fname)

@webui.route('/css/<path:fname>', methods=['GET'])
def css(fname):
    return send_from_directory(FRONT_DIR / 'css', fname)

@webui.route('/robots.txt', methods=['GET'])
def robots():
    f = FRONT_DIR / 'robots.txt'
    if f.exists():
        return send_from_directory(FRONT_DIR, 'robots.txt')
    return ('', 204)

@webui.route('/favicon.ico', methods=['GET'])
def favicon():
    f = FRONT_DIR / 'favicon.ico'
    if f.exists():
        return send_from_directory(FRONT_DIR, 'favicon.ico')
    return ('', 204)

# Opcional: páginas legales si existen
@webui.route('/terms.html', methods=['GET'])
def terms():
    f = FRONT_DIR / 'terms.html'
    if f.exists():
        return send_from_directory(FRONT_DIR, 'terms.html')
    return ('', 404)

@webui.route('/privacy.html', methods=['GET'])
def privacy():
    f = FRONT_DIR / 'privacy.html'
    if f.exists():
        return send_from_directory(FRONT_DIR, 'privacy.html')
    return ('', 404)
PY

echo "➤ Escribo backend/entry.py (WSGI estable)"
cat > backend/entry.py <<'PY'
from backend import create_app
try:
    from backend.webui import webui
except Exception:
    webui = None

app = create_app()
if webui is not None:
    try:
        app.register_blueprint(webui)
    except Exception:
        pass
PY

echo "➤ Escribo Procfile (Render usará este comando)"
cat > Procfile <<'TXT'
web: gunicorn -w 2 -k gthread -b 0.0.0.0:$PORT backend.entry:app
TXT

echo "➤ Smoke local con gunicorn (si existe)"
if command -v gunicorn >/dev/null 2>&1; then
  pkill -9 -f "gunicorn .*backend.entry:app" 2>/dev/null || true
  nohup gunicorn -b 127.0.0.1:8000 backend.entry:app >/dev/null 2>&1 & echo $! > "$PIDFILE"
  sleep 2
  for p in / "/js/app.js" "/css/styles.css" "/robots.txt" "/api/health"; do
    echo "--- $p"
    curl -sSI "http://127.0.0.1:8000$p" | head -n 12 || true
  done
  kill "$(cat "$PIDFILE" 2>/dev/null || echo)" 2>/dev/null || true
  rm -f "$PIDFILE" || true
else
  echo "(!) gunicorn no está instalado localmente; omito smoke local."
fi

echo "➤ Commit & push"
git add Procfile backend/entry.py backend/webui.py
git commit -m "deploy(web): Procfile + entry WSGI y blueprint frontend con /, /js, /css, robots, favicon"
git push origin main

echo "✓ Listo. Render quedará atado a backend.entry:app"
