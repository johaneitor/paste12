#!/usr/bin/env bash
set -Eeuo pipefail

INIT="backend/__init__.py"
WEBUI="backend/webui.py"
LOG="${TMPDIR:-/data/data/com.termux/files/usr/tmp}/paste12_server.log"
mkdir -p "$(dirname "$LOG")"

echo "➤ Backups"
cp -f "$INIT"  "$INIT.bak.$(date +%s)"  2>/dev/null || true

python - <<'PY'
from pathlib import Path, re
# 1) Crear/actualizar blueprint que sirve el frontend
webui = Path("backend/webui.py")
if not webui.exists():
    webui.write_text("""\
from flask import Blueprint, send_from_directory
from pathlib import Path

# FRONT_DIR: <repo>/frontend
FRONT_DIR = (Path(__file__).resolve().parent.parent / "frontend").resolve()

webui = Blueprint("webui", __name__)

@webui.route("/", methods=["GET"])
def index():
    return send_from_directory(FRONT_DIR, "index.html")

@webui.route("/js/<path:fname>", methods=["GET"])
def js(fname):
    return send_from_directory(FRONT_DIR / "js", fname)

@webui.route("/favicon.ico", methods=["GET"])
def favicon():
    p = FRONT_DIR / "favicon.ico"
    if p.exists():
        return send_from_directory(FRONT_DIR, "favicon.ico")
    return ("", 204)
""", encoding="utf-8")
    print("webui.py: creado.")
else:
    print("webui.py: ya existe (ok).")

# 2) Limpiar cualquier bloque estático viejo mal ubicado en __init__.py
initp = Path("backend/__init__.py")
s = initp.read_text(encoding="utf-8")
s2 = re.sub(r'\n# === Static frontend routes.*?^except\s+Exception.*?pass\s*$','\n',s,flags=re.S|re.M)
if s2 != s:
    s = s2
    print("__init__.py: bloque estático viejo removido.")

# 3) Inyectar wrapper de create_app para registrar el blueprint SIEMPRE
#    - Guardamos la original como _create_app_orig si aún no existe
if re.search(r'def\s+_create_app_orig\s*\(', s):
    print("__init__.py: wrapper ya presente (idempotente).")
else:
    m = re.search(r'(def\s+create_app\s*\([^)]*\)\s*:\s*)', s)
    if not m:
        raise SystemExit("No encontré 'def create_app(...)' en backend/__init__.py")

    # Renombrar create_app -> _create_app_orig
    s = re.sub(r'\bdef\s+create_app\b', 'def _create_app_orig', s, count=1)

    # Añadir el wrapper que llama a la original y registra el blueprint
    wrapper = """
# === Wrapper para registrar frontend después de crear la app ===
def create_app(*args, **kwargs):
    app = _create_app_orig(*args, **kwargs)
    try:
        from .webui import webui
        app.register_blueprint(webui)
    except Exception:
        # Si falta el frontend en el deploy, no romper el API
        pass
    return app
"""
    if not s.endswith("\n"):
        s += "\n"
    s += wrapper
    print("__init__.py: wrapper de create_app añadido.")

initp.write_text(s, encoding="utf-8")
PY

echo "➤ Restart local"
pkill -f "python .*run\\.py" 2>/dev/null || true
pkill -f "waitress" 2>/dev/null || true
pkill -f "gunicorn" 2>/dev/null || true
pkill -f "flask" 2>/dev/null || true
sleep 1
nohup python run.py >"$LOG" 2>&1 & disown || true
sleep 2

echo "➤ Smokes locales"
echo "— GET / —"
curl -sS -i http://127.0.0.1:8000/ | sed -n '1,12p'
echo
echo "— GET /js/app.js —"
curl -sS -i http://127.0.0.1:8000/js/app.js | sed -n '1,10p'
echo

echo "➤ Commit & Push"
git add backend/__init__.py backend/webui.py || true
git commit -m "fix(web): servir frontend vía blueprint y wrapper de create_app; compatible con gunicorn backend:create_app()" || true
git push origin main

echo "✓ Hecho. En Render, tras el deploy, / y /js/app.js deben devolver 200."
