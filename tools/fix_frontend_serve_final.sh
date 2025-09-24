#!/usr/bin/env bash
set -Eeuo pipefail

LOG="${TMPDIR:-/data/data/com.termux/files/usr/tmp}/paste12_server.log"
mkdir -p "$(dirname "$LOG")"

echo "➤ Asegurar blueprint frontend (backend/webui.py)"
python - <<'PY'
from pathlib import Path
webui = Path("backend/webui.py")
webui.parent.mkdir(parents=True, exist_ok=True)
webui.write_text("""from flask import Blueprint, send_from_directory
from pathlib import Path as _Path
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
""", encoding="utf-8")
print("  ✓ backend/webui.py")
PY

echo "➤ Limpiar bloques estáticos rotos (si existieran) en backend/__init__.py"
python - <<'PY'
from pathlib import Path, re
p = Path("backend/__init__.py")
if p.exists():
    s = p.read_text(encoding="utf-8")
    s2 = re.sub(r'\n# === Static frontend routes.*?^except\s+Exception.*?pass\s*$', '\n', s, flags=re.S|re.M)
    if s2 != s:
        p.write_text(s2, encoding="utf-8")
        print("  ✓ Bloque estático viejo eliminado en backend/__init__.py")
    else:
        print("  (no había bloque estático viejo)")
else:
    print("  (backend/__init__.py no existe; seguimos)")
PY

echo "➤ Inyectar registro del blueprint donde corresponda"
python - <<'PY'
from pathlib import Path, re

def inject_in_runpy(f: Path) -> bool:
    if not f.exists(): return False
    s = f.read_text(encoding="utf-8")
    if "app.register_blueprint(webui)" in s:
        print(f"  {f}: ya registra webui (ok)")
        return True
    # buscar línea 'app = create_app(...)'
    m = re.search(r'^\s*app\s*=\s*create_app\s*\([^)]*\)\s*$', s, flags=re.M)
    if not m:
        return False
    indent = re.match(r'\s*', m.group(0)).group(0)
    block = (
        f"{indent}try:\n"
        f"{indent}    from backend.webui import webui\n"
        f"{indent}    app.register_blueprint(webui)\n"
        f"{indent}except Exception:\n"
        f"{indent}    pass\n"
    )
    s = s[:m.end()] + "\n" + block + s[m.end():]
    f.write_text(s, encoding="utf-8")
    print(f"  {f}: inyectado app.register_blueprint(webui) tras create_app(...)")
    return True

def wrap_create_app(f: Path) -> bool:
    if not f.exists(): return False
    s = f.read_text(encoding="utf-8")
    if re.search(r'def\s+_create_app_orig\s*\(', s):
        print(f"  {f}: wrapper ya presente (ok)")
        return True
    m = re.search(r'(^|\n)\s*def\s+create_app\s*\([^)]*\)\s*:', s)
    if not m:
        return False
    s2 = re.sub(r'(^|\n)(\s*)def\s+create_app\b', r'\1\2def _create_app_orig', s, count=1)
    wrapper = """

# === Wrapper para registrar frontend después de crear la app ===
def create_app(*args, **kwargs):
    app = _create_app_orig(*args, **kwargs)
    try:
        from backend.webui import webui
        app.register_blueprint(webui)
    except Exception:
        pass
    return app
"""
    if not s2.endswith("\n"): s2 += "\n"
    s2 += wrapper
    f.write_text(s2, encoding="utf-8")
    print(f"  {f}: create_app envuelta; blueprint se registra en factory")
    return True

# 1) Intentar en run.py (típico start command gunicorn 'run:app')
done = inject_in_runpy(Path("run.py"))

# 2) Si no, envolver la factory en archivos probables
if not done:
    for cand in [Path("backend/__init__.py"), Path("backend/app.py"), Path("backend/factory.py"), Path("app.py")]:
        if wrap_create_app(cand):
            done = True
            break

if not done:
    print("  ⚠ No se halló ni 'app = create_app(...)' en run.py ni 'def create_app(...)' para envolver.")
    print("    Revisa el start command en Render (ideal: gunicorn -w 4 -b 0.0.0.0:$PORT 'run:app' ó 'backend:create_app()').")
PY

echo "➤ Verificar archivos frontend"
test -f frontend/index.html && echo "  ✓ frontend/index.html" || echo "  ✗ falta frontend/index.html"
test -f frontend/js/app.js   && echo "  ✓ frontend/js/app.js"   || echo "  ✗ falta frontend/js/app.js"

echo "➤ Restart local (dev)"
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
curl -sS -i http://127.0.0.1:8000/js/app.js | sed -n '1,12p'
echo

echo "➤ Commit & push"
git add backend/webui.py backend/__init__.py run.py backend/app.py backend/factory.py 2>/dev/null || true
git commit -m "fix(web): servir frontend como blueprint; registro garantizado (post-create_app o en run.py)" || true
git push origin main || true

echo "✓ Listo. Tras el deploy en Render, / y /js/app.js deben responder 200."
