#!/usr/bin/env bash
set -Eeuo pipefail

INIT="backend/__init__.py"
WEBUI="backend/webui.py"
FRONT_DIR="backend/frontend"
LOG="${TMPDIR:-/data/data/com.termux/files/usr/tmp}/paste12_server.log"
mkdir -p "$(dirname "$LOG")"

echo "➤ Backups"
cp -f "$INIT"  "$INIT.bak.$(date +%s)"  2>/dev/null || true
cp -f "$WEBUI" "$WEBUI.bak.$(date +%s)" 2>/dev/null || true

echo "➤ Asegurar frontend en $FRONT_DIR"
mkdir -p "$FRONT_DIR/js" "$FRONT_DIR/css"
# Copia index y js si existen en frontend/ raíz
[ -f "frontend/index.html" ] && cp -f "frontend/index.html" "$FRONT_DIR/index.html"
[ -f "frontend/js/app.js" ] && cp -f "frontend/js/app.js" "$FRONT_DIR/js/app.js"
# Stub CSS si no existe
if [ ! -f "$FRONT_DIR/css/styles.css" ]; then
  cat > "$FRONT_DIR/css/styles.css" <<'CSS'
:root { color-scheme: light dark; }
body { font-family: system-ui, sans-serif; margin: 0; padding: 16px; }
CSS
fi
# robots opcional
[ -f "frontend/robots.txt" ] && cp -f "frontend/robots.txt" "$FRONT_DIR/robots.txt"

echo "➤ Escribir/actualizar $WEBUI (blueprint robusto)"
cat > "$WEBUI" <<'PY'
from flask import Blueprint, send_from_directory
from pathlib import Path

def _discover_front_dir():
    pkg_dir = Path(__file__).resolve().parent  # .../backend
    candidates = [
        pkg_dir / "frontend",          # backend/frontend  (subdir deploy)
        pkg_dir.parent / "frontend",   # <repo>/frontend   (root deploy)
        Path.cwd() / "frontend",       # fallback
    ]
    for c in candidates:
        if c.exists():
            return c
    return candidates[0]

FRONT_DIR = _discover_front_dir()
webui = Blueprint("webui", __name__)

@webui.route("/", methods=["GET"])
def index():
    return send_from_directory(FRONT_DIR, "index.html")

@webui.route("/js/<path:fname>", methods=["GET"])
def js(fname):
    return send_from_directory(FRONT_DIR / "js", fname)

@webui.route("/css/<path:fname>", methods=["GET"])
def css(fname):
    return send_from_directory(FRONT_DIR / "css", fname)

@webui.route("/robots.txt", methods=["GET"])
def robots():
    p = FRONT_DIR / "robots.txt"
    if p.exists():
        return send_from_directory(FRONT_DIR, "robots.txt")
    return ("", 204)

def ensure_webui(app):
    """Registra el blueprint si aún no está registrado."""
    try:
        if "webui.index" not in app.view_functions:
            app.register_blueprint(webui)
    except Exception:
        # no romper el API si algo falla
        pass
PY

echo "➤ Inyectar registro del blueprint y /api/_routes en $INIT"
python - <<'PY'
from pathlib import Path
import re

p = Path("backend/__init__.py")
s = p.read_text(encoding="utf-8")

def put_once(haystack, needle, where_regex, before=False):
    if needle in haystack:
        return haystack
    m = re.search(where_regex, haystack, re.S|re.M)
    if not m:
        return haystack
    pos = m.start() if before else m.end()
    return haystack[:pos] + "\n" + needle + "\n" + haystack[pos:]

# 1) Registrar webui en app global si existe variable app
block_global = """try:
    from .webui import ensure_webui  # noqa
    ensure_webui(app)
except Exception:
    pass"""
s = put_once(s, block_global, r'\bapp\s*=\s*.+', before=False)

# 2) Registrar webui dentro de create_app(...) si existe
block_factory = """    try:
        from .webui import ensure_webui  # noqa
        ensure_webui(app)
    except Exception:
        pass"""
s = re.sub(
    r'(def\s+create_app\s*\([^)]*\)\s*:\s*\n\s*.*?\n)(\s*return\s+app\b)',
    lambda m: (m.group(1) + block_factory + "\n" + m.group(2)),
    s, flags=re.S
)

# 3) Exponer /api/_routes para diagnóstico si no existe
if "/api/_routes" not in s:
    s += """

# === Debug: listar rutas ===
try:
    @app.route("/api/_routes", methods=["GET"])
    def __routes__():
        out = []
        for r in app.url_map.iter_rules():
            methods = sorted(m for m in r.methods if m not in {"HEAD","OPTIONS"})
            out.append({"rule": r.rule, "methods": methods, "endpoint": r.endpoint})
        from flask import jsonify
        return jsonify({"routes": out}), 200
except Exception:
    pass
"""
p.write_text(s, encoding="utf-8")
print("init patched.")
PY

echo "➤ Restart local (dev)"
pkill -f "python .*run\\.py" 2>/dev/null || true
pkill -f "waitress" 2>/dev/null || true
pkill -f "gunicorn" 2>/dev/null || true
pkill -f "flask" 2>/dev/null || true
sleep 1
nohup python run.py >"$LOG" 2>&1 & disown || true
sleep 2

echo "➤ Smokes locales"
echo "-- HEAD / --"
curl -sSI http://127.0.0.1:8000/            | head -n 12
echo "-- HEAD /js/app.js --"
curl -sSI http://127.0.0.1:8000/js/app.js   | head -n 12
echo "-- HEAD /css/styles.css --"
curl -sSI http://127.0.0.1:8000/css/styles.css | head -n 12
echo "-- GET /api/_routes --"
curl -sS  http://127.0.0.1:8000/api/_routes | python -m json.tool | head -n 40 || true

echo "➤ Commit & push"
git add backend/__init__.py backend/webui.py backend/frontend/css/styles.css || true
git commit -m "fix(web): registrar blueprint webui en app global y create_app; servir /, /js/*, /css/*, robots.txt; exponer /api/_routes" || true
git push origin main || true

echo "✓ Hecho. En Render, con 'backend:app' o 'backend:create_app()', '/' y '/js/app.js' deben responder 200."
