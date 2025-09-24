#!/usr/bin/env bash
set -Eeuo pipefail

WEBUI="backend/webui.py"
INIT="backend/__init__.py"
LOG="${TMPDIR:-/data/data/com.termux/files/usr/tmp}/paste12_server.log"
mkdir -p "$(dirname "$LOG")"

echo "==> Backups"
cp -f "$WEBUI" "$WEBUI.bak.$(date +%s)" 2>/dev/null || true
cp -f "$INIT"  "$INIT.bak.$(date +%s)"  2>/dev/null || true

echo "==> Sincronizar frontend a backend/frontend (por compatibilidad con deploy en subdir)"
mkdir -p backend/frontend
if command -v rsync >/dev/null 2>&1; then
  rsync -a frontend/ backend/frontend/
else
  (cd frontend && tar cf - .) | (cd backend/frontend && tar xpf -)
fi

echo "==> Reescribir backend/webui.py con rutas completas (/, /js, /css, /favicon, /robots, /privacy, /terms)"
python - <<'PY'
from pathlib import Path
p = Path("backend/webui.py")
code = """\
from flask import Blueprint, send_from_directory
from pathlib import Path

# Detecta dónde está el frontend (soporta deploy con root en 'backend')
PKG_DIR = Path(__file__).resolve().parent  # .../backend
CANDIDATES = [
    PKG_DIR / "frontend",            # backend/frontend (deploy subdir)
    PKG_DIR.parent / "frontend",     # <repo>/frontend (deploy root)
    Path.cwd() / "frontend",         # fallback
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

@webui.route("/robots.txt", methods=["GET"])
def robots():
    p = FRONT_DIR / "robots.txt"
    if p.exists():
        return send_from_directory(FRONT_DIR, "robots.txt")
    return ("User-agent: *\\nAllow: /\\n", 200, {"Content-Type": "text/plain; charset=utf-8"})

@webui.route("/privacy.html", methods=["GET"])
def privacy():
    return send_from_directory(FRONT_DIR, "privacy.html")

@webui.route("/terms.html", methods=["GET"])
def terms():
    return send_from_directory(FRONT_DIR, "terms.html")
"""
p.write_text(code, encoding="utf-8")
print("webui.py actualizado.")
PY

echo "==> Inyectar registro de blueprint sobre la instancia 'app' que usa Gunicorn"
python - <<'PY'
from pathlib import Path, re
p = Path("backend/__init__.py")
s = p.read_text(encoding="utf-8")

# Ya registrado?
if re.search(r'app\.register_blueprint\(\s*webui\s*\)', s):
    print("__init__.py ya registraba webui (ok).")
else:
    # Buscar la PRIMERA asignación a 'app = ...' y registrar justo después.
    m = re.search(r'^(?P<indent>\s*)app\s*=\s*.+$', s, flags=re.M)
    if not m:
        raise SystemExit("No encontré 'app = ...' en backend/__init__.py; ajusta el start command a backend:create_app() o añade app = create_app().")
    indent = m.group('indent')
    inject = (
        "\n{0}# registrar blueprint del frontend\n"
        "{0}try:\n"
        "{0}    from .webui import webui\n"
        "{0}    app.register_blueprint(webui)\n"
        "{0}except Exception:\n"
        "{0}    pass\n"
    ).format(indent)
    idx = m.end()
    s = s[:idx] + inject + s[idx:]
    p.write_text(s, encoding="utf-8")
    print("__init__.py: blueprint registrado tras 'app = ...'.")
PY

echo "==> Restart local para probar"
pkill -f "python .*run\\.py" 2>/dev/null || true
pkill -f waitress 2>/dev/null || true
pkill -f gunicorn 2>/dev/null || true
pkill -f flask 2>/dev/null || true
sleep 1
nohup python run.py >"$LOG" 2>&1 & disown || true
sleep 2

echo "-- / --"
curl -sS -i http://127.0.0.1:8000/ | sed -n '1,12p'
echo
echo "-- /js/app.js --"
curl -sS -i http://127.0.0.1:8000/js/app.js | sed -n '1,12p'
echo

echo "==> Commit & push"
git add backend/webui.py backend/__init__.py backend/frontend || true
git commit -m "fix(web): registrar blueprint del frontend en backend/__init__.py y servir /, /js, /css, /robots, /privacy, /terms (Render compatible)" || true
git push origin main || true

cat <<'NOTE'

Listo:
- En Render, verifica que el Start command sea:
  gunicorn -w 4 -k gthread -b 0.0.0.0:$PORT backend:app

- Luego prueba:
  BASE="https://paste12-rmsk.onrender.com"
  curl -sSI "$BASE/" | sed -n '1,15p'
  curl -sSI "$BASE/js/app.js" | sed -n '1,15p'
  curl -sSI "$BASE/css/styles.css" | sed -n '1,15p'

Si vieras 404 aún, el Start command podría seguir apuntando a otro objeto (p.ej. backend:create_app()). En ese caso,
o cambias el Start command a backend:app, o repetimos el registro para la factory (wrapper).
NOTE
