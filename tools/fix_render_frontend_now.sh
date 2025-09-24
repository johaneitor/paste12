#!/usr/bin/env bash
set -Eeuo pipefail

echo "➤ Sync frontend into backend/frontend"
mkdir -p backend/frontend/js backend/frontend/css

# Copiar index.html y app.js si existen en /frontend
[ -f frontend/index.html ] && cp -f frontend/index.html backend/frontend/index.html || true
[ -f frontend/js/app.js ] && cp -f frontend/js/app.js backend/frontend/js/app.js || true

# CSS mínimo si no existe
if [ ! -f backend/frontend/css/styles.css ]; then
  cat > backend/frontend/css/styles.css <<'CSS'
:root{color-scheme:dark light}body{font-family:system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,Helvetica,Arial,sans-serif;margin:0;background:#0d1320;color:#eaf2ff}
main{max-width:720px;margin:28px auto;padding:16px}
.load-more{cursor:pointer}
CSS
fi

# robots.txt (opcional)
[ -f backend/frontend/robots.txt ] || printf "User-agent: *\nAllow: /\n" > backend/frontend/robots.txt

# favicon (opcional - no obligatorio)
[ -f backend/frontend/favicon.ico ] || true

echo "➤ Write backend/webui.py (robusto)"
cat > backend/webui.py <<'PY'
from flask import Blueprint, send_from_directory
from pathlib import Path

PKG_DIR = Path(__file__).resolve().parent  # .../backend
CANDIDATES = [
    PKG_DIR / "frontend",          # backend/frontend (usual en Render)
    PKG_DIR.parent / "frontend",   # <repo>/frontend
    Path.cwd() / "frontend",       # fallback
]
for c in CANDIDATES:
    if c.exists():
        FRONT_DIR = c
        break
else:
    FRONT_DIR = CANDIDATES[0]

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
PY

echo "➤ Write backend/entry.py (WSGI con fallback de rutas estáticas)"
cat > backend/entry.py <<'PY'
# Punto de entrada WSGI estable para Render: backend.entry:app
from pathlib import Path
try:
    # Preferimos factory si existe
    from backend import create_app as _factory  # type: ignore
except Exception:
    _factory = None

app = None
if _factory:
    try:
        app = _factory()
    except Exception:
        app = None

if app is None:
    # Fallback a 'app' global si la app no es factory o si falló
    from backend import app as _app  # type: ignore
    app = _app

# Intentar registrar el blueprint webui
try:
    from backend.webui import webui  # type: ignore
    app.register_blueprint(webui)    # type: ignore[attr-defined]
except Exception:
    # Fallback duro: definir rutas estáticas inline
    from flask import send_from_directory
    PKG_DIR = Path(__file__).resolve().parent
    candidates = [
        PKG_DIR / "frontend",
        PKG_DIR.parent / "frontend",
        Path.cwd() / "frontend",
    ]
    for c in candidates:
        if c.exists():
            FRONT_DIR = c
            break
    else:
        FRONT_DIR = candidates[0]

    @app.get("/")  # type: ignore[misc]
    def _index():
        return send_from_directory(FRONT_DIR, "index.html")

    @app.get("/js/<path:fname>")  # type: ignore[misc]
    def _js(fname):
        return send_from_directory(FRONT_DIR / "js", fname)

    @app.get("/css/<path:fname>")  # type: ignore[misc]
    def _css(fname):
        return send_from_directory(FRONT_DIR / "css", fname)

    @app.get("/robots.txt")  # type: ignore[misc]
    def _robots():
        p = FRONT_DIR / "robots.txt"
        return (send_from_directory(FRONT_DIR, "robots.txt") if p.exists() else ("", 204))

    @app.get("/favicon.ico")  # type: ignore[misc]
    def _favicon():
        p = FRONT_DIR / "favicon.ico"
        return (send_from_directory(FRONT_DIR, "favicon.ico") if p.exists() else ("", 204))
PY

echo "➤ Write Procfile (Render Start Command)"
cat > Procfile <<'TXT'
web: gunicorn -w 4 -k gthread -b 0.0.0.0:$PORT backend.entry:app
TXT

echo "➤ Commit & push"
git add Procfile backend/entry.py backend/webui.py backend/frontend || true
git commit -m "fix(render): WSGI entry con fallback estatico y frontend en backend/frontend; Procfile gunicorn" || true
git push origin main

echo "➤ Verificación remota (HEAD a rutas clave)"
BASE="${1:-https://paste12-rmsk.onrender.com}"
for p in / "/js/app.js" "/css/styles.css" "/robots.txt" "/api/health"; do
  echo "--- $p"
  curl -sSI "$BASE$p" | head -n 12 || true
done

echo "✔ Listo. Si / sigue 404 inmediatamente, el push ya disparó deploy; volvé a correr este bloque de HEAD en unos segundos."
