#!/usr/bin/env bash
set -Eeuo pipefail

echo "➤ Escribo wsgi.py (reexporta la app real)"
cat > wsgi.py <<'PY'
from backend.entry import app
PY

echo "➤ Escribo backend/entry.py (entrypoint robusto)"
mkdir -p backend
cat > backend/entry.py <<'PY'
from pathlib import Path

app = None
try:
    from backend import create_app as _factory  # type: ignore
except Exception:
    _factory = None

if _factory:
    try:
        app = _factory()
    except Exception:
        app = None

if app is None:
    from backend import app as _app  # type: ignore
    app = _app

try:
    from backend.webui import ensure_webui  # type: ignore
    ensure_webui(app)  # type: ignore
except Exception:
    try:
        from flask import send_from_directory
        PKG_DIR = Path(__file__).resolve().parent
        candidates = [PKG_DIR/"frontend", PKG_DIR.parent/"frontend", Path.cwd()/"frontend"]
        FRONT_DIR = next((c for c in candidates if c.exists()), candidates[0])

        @app.get("/")            # type: ignore
        def _index(): return send_from_directory(FRONT_DIR, "index.html")
        @app.get("/js/<path:f>") # type: ignore
        def _js(f): return send_from_directory(FRONT_DIR/"js", f)
        @app.get("/css/<path:f>")# type: ignore
        def _css(f): return send_from_directory(FRONT_DIR/"css", f)
        @app.get("/robots.txt")  # type: ignore
        def _robots():
            p = FRONT_DIR/"robots.txt"
            return (send_from_directory(FRONT_DIR, "robots.txt") if p.exists() else ("", 204))
        @app.get("/favicon.ico") # type: ignore
        def _ico():
            p = FRONT_DIR/"favicon.ico"
            return (send_from_directory(FRONT_DIR, "favicon.ico") if p.exists() else ("", 204))
    except Exception:
        pass
PY

echo "➤ Asegurar blueprint y assets frontend mínimos"
mkdir -p backend/frontend/js backend/frontend/css
cat > backend/webui.py <<'PY'
from flask import Blueprint, send_from_directory
from pathlib import Path

def _front_dir():
    pkg = Path(__file__).resolve().parent
    for c in (pkg/"frontend", pkg.parent/"frontend", Path.cwd()/"frontend"):
        if c.exists(): return c
    return pkg/"frontend"

FRONT_DIR = _front_dir()
webui = Blueprint("webui", __name__)

@webui.get("/")
def index(): return send_from_directory(FRONT_DIR, "index.html")

@webui.get("/js/<path:fname>")
def js(fname): return send_from_directory(FRONT_DIR/"js", fname)

@webui.get("/css/<path:fname>")
def css(fname): return send_from_directory(FRONT_DIR/"css", fname)

@webui.get("/robots.txt")
def robots():
    p = FRONT_DIR/"robots.txt"
    return (send_from_directory(FRONT_DIR,"robots.txt") if p.exists() else ("",204))

@webui.get("/favicon.ico")
def favicon():
    p = FRONT_DIR/"favicon.ico"
    return (send_from_directory(FRONT_DIR,"favicon.ico") if p.exists() else ("",204))

def ensure_webui(app):
    try:
        if "webui.index" not in app.view_functions:
            app.register_blueprint(webui)
    except Exception:
        pass
PY

cat > backend/frontend/index.html <<'HTML'
<!doctype html><html><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>paste12</title>
<link rel="stylesheet" href="/css/styles.css">
</head><body>
<main class="wrap">
  <h1>paste12</h1>
  <p>Frontend OK ✅ — API <code>/api/health</code> debería dar 200.</p>
  <script src="/js/app.js"></script>
</main>
</body></html>
HTML
cat > backend/frontend/css/styles.css <<'CSS'
body{font-family:system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,"Helvetica Neue",Arial,sans-serif;margin:0;padding:2rem;background:#0b1020;color:#e6ecff}
.wrap{max-width:720px;margin:0 auto}
h1{margin:0 0 1rem 0}
code{background:#111834;padding:.1rem .3rem;border-radius:.3rem}
CSS
cat > backend/frontend/js/app.js <<'JS'
console.log("paste12 frontend alive");
JS

echo "➤ Endpoint de diagnóstico /api/runtime (en el blueprint API)"
# Añade si no existe ya
if ! grep -q "def runtime()" backend/routes.py 2>/dev/null; then
  cat >> backend/routes.py <<'PY'

# --- runtime diag ---
try:
    from flask import current_app, jsonify
    @api.route("/api/runtime", methods=["GET"])  # type: ignore
    def runtime():
        import sys
        try:
            from backend.webui import FRONT_DIR as _FD  # type: ignore
            front_dir = str(_FD); front_dir_exists = _FD.exists()
        except Exception:
            front_dir, front_dir_exists = None, False
        rules = sorted(
            [{"rule": r.rule, "methods": sorted(r.methods)} for r in current_app.url_map.iter_rules()],
            key=lambda x: x["rule"]
        )
        return jsonify({
            "uses_backend_entry": "backend.entry" in sys.modules,
            "has_root_route": any(r["rule"]=="/" for r in rules),
            "front_dir": front_dir,
            "front_dir_exists": front_dir_exists,
            "rules_sample": rules[:50],
        })
except Exception:
    pass
PY
fi

echo "➤ Procfile forzado a wsgi:app"
echo 'web: gunicorn -w 2 -k gthread -b 0.0.0.0:$PORT wsgi:app' > Procfile

echo "➤ render.yaml para Blueprint deploy (fija startCommand)"
cat > render.yaml <<'YAML'
services:
  - type: web
    name: paste12
    env: python
    plan: free
    buildCommand: pip install -r requirements.txt
    startCommand: gunicorn -w 2 -k gthread -b 0.0.0.0:$PORT wsgi:app
    healthCheckPath: /api/health
    autoDeploy: true
YAML

echo "➤ Commit & push"
git add wsgi.py backend/entry.py backend/webui.py backend/frontend Procfile render.yaml backend/routes.py || true
git commit -m "fix: forzar entry wsgi:app + frontend blueprint + render.yaml; agrega /api/runtime de diagnóstico" || true
git push origin main || true

echo "✓ Listo. Crea/rehaz el servicio desde 'Blueprint' en Render (render.yaml) y probá:"
echo '  curl -sS https://<tu-app>.onrender.com/api/runtime | python -m json.tool'
