#!/usr/bin/env bash
set -Eeuo pipefail

INIT="backend/__init__.py"
WEBUI="backend/webui.py"
LOG="${TMPDIR:-/data/data/com.termux/files/usr/tmp}/paste12_server.log"
mkdir -p "$(dirname "$LOG")"

echo "➤ Backups"
cp -f "$INIT" "$INIT.bak.$(date +%s)" 2>/dev/null || true

echo "➤ Restaurar __init__.py al último commit (HEAD)"
git restore --source=HEAD -- "$INIT" 2>/dev/null || git checkout -- "$INIT"

# Asegurar backend/webui.py (blueprint que sirve /, /js/*, /css/*, /favicon.ico)
python - <<'PY'
from pathlib import Path
p = Path("backend/webui.py")
if not p.exists():
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text('''\
from flask import Blueprint, send_from_directory
from pathlib import Path

# Detecta carpeta frontend (soporta deploy con root en repo o en backend/)
PKG_DIR = Path(__file__).resolve().parent        # .../backend
CANDIDATES = [
    PKG_DIR / "frontend",                        # backend/frontend
    PKG_DIR.parent / "frontend",                 # <repo>/frontend
    Path.cwd() / "frontend",                     # fallback
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
    return ("User-agent: *\nAllow: /\n", 200, {"Content-Type": "text/plain"})
''', encoding="utf-8")
    print("webui.py: creado.")
else:
    print("webui.py: ok")
PY

# Adjuntar blueprint sin reindentaciones peligrosas: global + factory wrapper
python - <<'PY'
from pathlib import Path, re
p = Path("backend/__init__.py")
s = p.read_text(encoding="utf-8")

patch = r'''
# === Adjuntar blueprint del frontend (global y factory) ===
try:
    from .webui import webui
    # Caso app global (gunicorn backend:app)
    if 'app' in globals():
        try:
            app.register_blueprint(webui)  # type: ignore[name-defined]
        except Exception:
            pass
    # Caso factory (gunicorn backend:create_app())
    if 'create_app' in globals() and callable(create_app):
        def _wrap_create_app(_orig):
            def _inner(*args, **kwargs):
                app = _orig(*args, **kwargs)
                try:
                    app.register_blueprint(webui)
                except Exception:
                    pass
                return app
            return _inner
        # Evitar doble wrap
        if getattr(create_app, '__name__', '') != '_inner':
            create_app = _wrap_create_app(create_app)  # type: ignore
except Exception:
    # No romper el API si falta frontend
    pass
'''.strip("\n")

if patch not in s:
    if not s.endswith("\n"): s += "\n"
    s += patch + "\n"

# Validar sintaxis
compile(s, str(p), 'exec')
p.write_text(s, encoding="utf-8")
print("init.py: parche adjuntado y sintaxis OK.")
PY

echo "➤ Restart local"
pkill -9 -f "python .*run\\.py" 2>/dev/null || true
pkill -9 -f gunicorn 2>/dev/null || true
pkill -9 -f waitress 2>/dev/null || true
pkill -9 -f flask 2>/dev/null || true
sleep 1
nohup python -u run.py >"$LOG" 2>&1 & disown || true
sleep 2

echo "➤ Smoke"
curl -sS -o /dev/null -w 'health=%{http_code}\n' http://127.0.0.1:8000/api/health || true
for p in / "/js/app.js" "/css/styles.css" "/robots.txt"; do
  echo "--- $p"
  curl -sSI "http://127.0.0.1:8000$p" | sed -n '1,12p' || true
done

echo "➤ Commit & push"
git add backend/__init__.py backend/webui.py || true
git commit -m "fix(web): adjuntar blueprint frontend sin tocar create_app (global+factory); webui robusto" || true
git push origin main || true

echo "✓ Listo."
