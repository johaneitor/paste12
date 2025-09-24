#!/usr/bin/env bash
set -Eeuo pipefail

LOG="${TMPDIR:-/data/data/com.termux/files/usr/tmp}/paste12_server.log"
mkdir -p "$(dirname "$LOG")"

echo "➤ Crear/actualizar blueprint backend/webui.py"
python - <<'PY'
from pathlib import Path
p = Path("backend/webui.py")
if not p.parent.exists():
    raise SystemExit("No existe la carpeta backend/ (estructura inesperada)")
if not p.exists():
    p.write_text(
        """from flask import Blueprint, send_from_directory
from pathlib import Path as _Path

# FRONT_DIR: <repo>/frontend
FRONT_DIR = (_Path(__file__).resolve().parent.parent / "frontend").resolve()

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
""",
        encoding="utf-8",
    )
    print("  webui.py: creado.")
else:
    print("  webui.py: ya existía (ok).")
PY

echo "➤ Buscar e inyectar wrapper de create_app(...)"
python - <<'PY'
from pathlib import Path
import re, sys

# Archivos candidatos probables + scan general de backend/
candidates = [
    Path("backend/__init__.py"),
    Path("backend/app.py"),
    Path("backend/factory.py"),
    Path("run.py"),
    Path("app.py"),
]
backend_dir = Path("backend")
if backend_dir.exists():
    for q in backend_dir.rglob("*.py"):
        if q not in candidates:
            candidates.append(q)

patched = None
for f in candidates:
    if not f.exists():
        continue
    s = f.read_text(encoding="utf-8")

    # ya wrapper?
    if re.search(r'def\s+_create_app_orig\s*\(', s):
        print(f"  {f}: wrapper ya presente (idempotente).")
        patched = patched or f
        continue

    # hay create_app?
    m = re.search(r'(^|\n)\s*def\s+create_app\s*\([^)]*\)\s*:', s)
    if not m:
        continue

    # backup
    bak = f.with_suffix(f.suffix + f".bak")
    f.write_text(s, encoding="utf-8")  # ensure we can write later; keep original now as "original"

    # renombrar primera def create_app -> _create_app_orig
    s2 = re.sub(r'(^|\n)(\s*)def\s+create_app\b', r'\1\2def _create_app_orig', s, count=1)

    wrapper = """

# === Wrapper para registrar frontend después de crear la app ===
def create_app(*args, **kwargs):
    app = _create_app_orig(*args, **kwargs)
    try:
        from backend.webui import webui
        app.register_blueprint(webui)
    except Exception:
        # Si falta el frontend en el deploy, no romper el API
        pass
    return app
"""
    if not s2.endswith("\n"):
        s2 += "\n"
    s2 += wrapper

    f.write_text(s2, encoding="utf-8")
    print(f"  {f}: wrapper insertado.")
    patched = f
    break

if not patched:
    print("  ⚠ No encontré ninguna 'def create_app(...)' en el repo.")
    print("    Revisa tu comando de arranque de Render (p.ej. gunicorn 'backend:create_app()').")
PY

echo "➤ Verificar que el frontend exista en el repo"
test -f frontend/index.html && echo "  ✓ frontend/index.html" || echo "  ✗ falta frontend/index.html"
test -f frontend/js/app.js   && echo "  ✓ frontend/js/app.js"   || echo "  ✗ falta frontend/js/app.js"

echo "➤ Restart local"
pkill -f "python .*run\\.py" 2>/dev/null || true
pkill -f gunicorn 2>/dev/null || true
pkill -f waitress 2>/dev/null || true
pkill -f flask 2>/dev/null || true
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
git add backend/webui.py backend/**/*.py run.py 2>/dev/null || true
git commit -m "fix(web): servir frontend con blueprint y wrapper de create_app (busca e inyecta en archivo de fábrica)" || true
git push origin main || true

echo "✓ Hecho. Tras el deploy en Render, / y /js/app.js deben responder 200."
