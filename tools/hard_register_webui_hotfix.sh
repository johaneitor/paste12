#!/usr/bin/env bash
set -Eeuo pipefail

INIT="backend/__init__.py"
WEBUI="backend/webui.py"
FRONT="frontend"
FRONT_BACKEND="backend/frontend"
LOG="${TMPDIR:-/data/data/com.termux/files/usr/tmp}/paste12_server.log"
mkdir -p "$(dirname "$LOG")"

echo "➤ Backups"
cp -f "$INIT" "$INIT.bak.$(date +%s)" 2>/dev/null || true

echo "➤ Copiar frontend a $FRONT_BACKEND (compat Render)"
mkdir -p "$FRONT_BACKEND"
if command -v rsync >/dev/null 2>&1; then
  rsync -a "$FRONT/." "$FRONT_BACKEND/"
else
  (cd "$FRONT" && tar cf - .) | (cd "$FRONT_BACKEND" && tar xpf -)
fi

echo "➤ Escribir backend/webui.py"
python - <<'PY'
from pathlib import Path
p = Path("backend/webui.py")
p.write_text("""\
from flask import Blueprint, send_from_directory
from pathlib import Path

PKG_DIR = Path(__file__).resolve().parent
CANDIDATES = [
    PKG_DIR / 'frontend',           # backend/frontend
    PKG_DIR.parent / 'frontend',    # <repo>/frontend
    Path.cwd() / 'frontend',        # fallback
]
for _cand in CANDIDATES:
    if _cand.exists():
        FRONT_DIR = _cand
        break
else:
    FRONT_DIR = CANDIDATES[0]

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

@webui.route("/favicon.ico", methods=["GET"])
def favicon():
    p = FRONT_DIR / "favicon.ico"
    if p.exists():
        return send_from_directory(FRONT_DIR, "favicon.ico")
    return ("", 204)
""", encoding="utf-8")
print("webui.py OK")
PY

echo "➤ Inyectar registro del blueprint en backend/__init__.py (global + factory + fallback)"
python - <<'PY'
import re
from pathlib import Path

p = Path("backend/__init__.py")
s = p.read_text(encoding="utf-8")

# Quitar bloques estáticos viejos
s = re.sub(r'\n# === Static frontend routes.*?^except\s+Exception.*?pass\s*$','\n',s,flags=re.S|re.M)

changed = False

# 1) MODO APP GLOBAL: insertar tras la primera asignación app = Flask(...)
if 'app.register_blueprint(webui)' not in s:
    m = re.search(r'\bapp\s*=\s*Flask\s*\(.*?\)', s, flags=re.S)
    if m:
        inject = """
# -- webui: registrar blueprint (modo app global) --
try:
    from .webui import webui
    if 'webui' not in app.blueprints:
        app.register_blueprint(webui)
except Exception:
    pass
"""
        s = s[:m.end()] + inject + s[m.end():]
        changed = True

# 2) FACTORY: renombrar create_app -> _create_app_orig y envolver
if 'def create_app' in s and 'def _create_app_orig' not in s:
    s = re.sub(r'\bdef\s+create_app\b', 'def _create_app_orig', s, count=1)
    wrapper = """
# === Wrapper para registrar frontend tras create_app() ===
def create_app(*args, **kwargs):
    app = _create_app_orig(*args, **kwargs)
    try:
        from .webui import webui
        if 'webui' not in app.blueprints:
            app.register_blueprint(webui)
    except Exception:
        pass
    return app
"""
    if not s.endswith("\n"): s += "\n"
    s += wrapper
    changed = True

# 3) Fallback defensivo (idempotente)
if "Fallback defensivo: registrar webui" not in s:
    fallback = """
# === Fallback defensivo: registrar webui si no quedó registrado ===
try:
    from .webui import webui
    if 'webui' not in app.blueprints:
        app.register_blueprint(webui)
except Exception:
    pass
"""
    if not s.endswith("\n"): s += "\n"
    s += fallback
    changed = True

p.write_text(s, encoding="utf-8")
print("__init__.py actualizado.")
PY

echo "➤ Restart local"
pkill -f "python .*run\\.py" 2>/dev/null || true
pkill -f "waitress" 2>/dev/null      || true
pkill -f "gunicorn" 2>/dev/null      || true
pkill -f "flask" 2>/dev/null         || true
sleep 1
nohup python run.py >"$LOG" 2>&1 & disown || true
sleep 2

echo "-- HEAD / --"
curl -sSI 'http://127.0.0.1:8000/' | sed -n '1,12p'
echo "-- HEAD /js/app.js --"
curl -sSI 'http://127.0.0.1:8000/js/app.js' | sed -n '1,12p'
echo "-- HEAD /css/styles.css --"
curl -sSI 'http://127.0.0.1:8000/css/styles.css' | sed -n '1,12p'

echo "➤ Commit & push"
git add backend/__init__.py backend/webui.py backend/frontend || true
git commit -m "fix(web): hotfix registro webui sin re.split; soporta backend:app y backend:create_app()" || true
git push origin main || true

echo "✓ Hecho."
