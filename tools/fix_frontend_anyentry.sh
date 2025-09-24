#!/usr/bin/env bash
set -Eeuo pipefail

WEBUI="backend/webui.py"
INIT="backend/__init__.py"
LOG="${TMPDIR:-/data/data/com.termux/files/usr/tmp}/paste12_server.log"
mkdir -p "$(dirname "$LOG")"

echo "==> Backups"
cp -f "$WEBUI" "$WEBUI.bak.$(date +%s)" 2>/dev/null || true
cp -f "$INIT"  "$INIT.bak.$(date +%s)"  2>/dev/null || true

echo "==> Sincronizar frontend a backend/frontend (compat Render)"
mkdir -p backend/frontend
if command -v rsync >/dev/null 2>&1; then
  rsync -a frontend/ backend/frontend/
else
  (cd frontend && tar cf - .) | (cd backend/frontend && tar xpf -)
fi

echo "==> Escribir backend/webui.py completo"
python - <<'PY'
from pathlib import Path
p = Path("backend/webui.py")
code = """\
from flask import Blueprint, send_from_directory
from pathlib import Path

PKG_DIR = Path(__file__).resolve().parent  # .../backend
CANDIDATES = [
    PKG_DIR / "frontend",            # backend/frontend
    PKG_DIR.parent / "frontend",     # <repo>/frontend
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
print("webui.py OK")
PY

echo "==> Inyectar registro del blueprint para ambos modos (app global y factory)"
python - <<'PY'
from pathlib import Path, re
p = Path("backend/__init__.py")
s = p.read_text(encoding="utf-8")

changed = False

# 1) Si hay una app global, registrar blueprint tras la asignación.
if not re.search(r'app\.register_blueprint\(\s*webui\s*\)', s):
    m = re.search(r'^(?P<indent>\s*)app\s*=\s*.+$', s, flags=re.M)
    if m:
        indent = m.group('indent')
        inject = (
            "\n{0}# registrar blueprint del frontend\n"
            "{0}try:\n"
            "{0}    from .webui import webui\n"
            "{0}    app.register_blueprint(webui)\n"
            "{0}except Exception:\n"
            "{0}    pass\n"
        ).format(indent)
        s = s[:m.end()] + inject + s[m.end():]
        changed = True

# 2) Si hay factory create_app, envolverla con wrapper (solo si aún no está envuelta).
if not re.search(r'def\s+_create_app_orig\s*\(', s):
    if re.search(r'^\s*def\s+create_app\s*\(', s, flags=re.M):
        s = re.sub(r'(^\s*def\s+)create_app(\s*\()', r'\1_create_app_orig\2', s, count=1, flags=re.M)
        wrapper = """
# === Wrapper para registrar frontend en la factory ===
def create_app(*args, **kwargs):
    app = _create_app_orig(*args, **kwargs)
    try:
        from .webui import webui
        app.register_blueprint(webui)
    except Exception:
        pass
    return app
"""
        if not s.endswith("\n"):
            s += "\n"
        s += wrapper
        changed = True

if changed:
    p.write_text(s, encoding="utf-8")
    print("__init__.py actualizado")
else:
    print("__init__.py sin cambios (ya estaba bien)")
PY

echo "==> Restart local"
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
git commit -m "fix(web): servir frontend y registrar blueprint tanto en app global como en create_app() (Render safe)" || true
git push origin main || true

cat <<'NEXT'
Ahora en Render:
- Si tu Start command es con objeto WSGI:  gunicorn -w 4 -k gthread -b 0.0.0.0:$PORT backend:app
- Si usas factory:                        gunicorn -w 4 -k gthread -b 0.0.0.0:$PORT backend:create_app()

Y prueba (en líneas separadas):
  BASE="https://paste12-rmsk.onrender.com"
  curl -sSI "$BASE/" | sed -n '1,15p'
  curl -sSI "$BASE/js/app.js" | sed -n '1,15p'
  curl -sSI "$BASE/css/styles.css" | sed -n '1,15p'
NEXT
