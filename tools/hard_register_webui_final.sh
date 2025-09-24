#!/usr/bin/env bash
set -Eeuo pipefail

INIT="backend/__init__.py"
WEBUI="backend/webui.py"
FRONT="frontend"
FRONT_BACKEND="backend/frontend"
LOG="${TMPDIR:-/data/data/com.termux/files/usr/tmp}/paste12_server.log"
mkdir -p "$(dirname "$LOG")"

echo "➤ Backups"
cp -f "$INIT"  "$INIT.bak.$(date +%s)"  2>/dev/null || true

echo "➤ Asegurar frontend copiado a ${FRONT_BACKEND}"
mkdir -p "$FRONT_BACKEND"
if command -v rsync >/dev/null 2>&1; then
  rsync -a "$FRONT/." "$FRONT_BACKEND/"
else
  (cd "$FRONT" && tar cf - .) | (cd "$FRONT_BACKEND" && tar xpf -)
fi

echo "➤ Escribir/actualizar backend/webui.py (blueprint robusto)"
python - <<'PY'
from pathlib import Path
p = Path("backend/webui.py")
p.write_text("""\
from flask import Blueprint, send_from_directory
from pathlib import Path

PKG_DIR = Path(__file__).resolve().parent  # .../backend
CANDIDATES = [
    PKG_DIR / 'frontend',           # backend/frontend  (copiado para Render)
    PKG_DIR.parent / 'frontend',    # <repo>/frontend   (dev local)
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
print("webui.py: OK")
PY

echo "➤ Inyectar registro del blueprint en backend/__init__.py (global y factory)"
python - <<'PY'
from pathlib import Path, re

initp = Path("backend/__init__.py")
s = initp.read_text(encoding="utf-8")

# 1) Limpiar cualquier bloque estático viejo de rutas mal ubicadas
s = re.sub(r'\n# === Static frontend routes.*?^except\s+Exception.*?pass\s*$','\n',s,flags=re.S|re.M)

# 2) Registro para APP GLOBAL:
#    Insertar un "try: app.register_blueprint(webui)" justo después de la PRIMERA asignación app = Flask(
pat_app = re.compile(r'(\bapp\s*=\s*Flask\s*\(.*?\)\s*)', re.S)
if pat_app.search(s):
    head, tail = pat_app.split(s, maxsplit=1)
    first_assign = pat_app.search(s).group(1)
    inject_global = """
# -- webui: registrar blueprint (modo app global) --
try:
    from .webui import webui
    if 'webui' not in app.blueprints:
        app.register_blueprint(webui)
except Exception:
    pass
"""
    s = head + first_assign + inject_global + tail

# 3) Registro para FACTORY create_app(...):
#    Si existe def create_app, envolver su retorno registrando el blueprint.
if re.search(r'\bdef\s+create_app\s*\(', s):
    # Solo añadir si aún no hay wrapper evidente
    if "register_blueprint(webui)" not in s or "create_app(" in s and "_create_app_orig(" not in s:
        s = re.sub(r'\bdef\s+create_app\s*\(([^)]*)\)\s*:\s*',
                   r'def _create_app_orig(\1):\n    ',
                   s, count=1)
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

# 4) Fallback defensivo: al final, intentar registrar por si acaso (idempotente)
fallback = """
# === Fallback defensivo: registrar webui si no quedó registrado ===
try:
    from .webui import webui
    if 'webui' not in app.blueprints:
        app.register_blueprint(webui)
except Exception:
    pass
"""
if "Fallback defensivo" not in s:
    if not s.endswith("\n"): s += "\n"
    s += fallback

initp.write_text(s, encoding="utf-8")
print("__init__.py: inyectado (global + factory + fallback)")
PY

echo "➤ Restart local (dev)"
pkill -f "python .*run\\.py" 2>/dev/null || true
pkill -f "waitress" 2>/dev/null || true
pkill -f "gunicorn" 2>/dev/null || true
pkill -f "flask" 2>/dev/null || true
sleep 1
nohup python run.py >"$LOG" 2>&1 & disown || true
sleep 2

echo "-- HEAD / --"
curl -sSI 'http://127.0.0.1:8000/' | sed -n '1,12p'
echo
echo "-- HEAD /js/app.js --"
curl -sSI 'http://127.0.0.1:8000/js/app.js' | sed -n '1,12p'
echo
echo "-- HEAD /css/styles.css --"
curl -sSI 'http://127.0.0.1:8000/css/styles.css' | sed -n '1,12p'
echo

echo "➤ Commit & push"
git add backend/__init__.py backend/webui.py backend/frontend || true
git commit -m "fix(web/render): registrar blueprint webui en modo global y factory; copiar frontend a backend/frontend; servir /, /js, /css siempre" || true
git push origin main || true

echo "✓ Hecho."
