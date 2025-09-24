#!/usr/bin/env bash
set -Eeuo pipefail

INIT="backend/__init__.py"
RUNPY="run.py"
LOG="${TMPDIR:-/data/data/com.termux/files/usr/tmp}/paste12_server.log"
mkdir -p "$(dirname "$LOG")"

echo "➤ Backups"
cp -f "$INIT"  "$INIT.bak.$(date +%s)"  2>/dev/null || true
cp -f "$RUNPY" "$RUNPY.bak.$(date +%s)" 2>/dev/null || true

python - <<'PY'
from pathlib import Path
import re

# 1) Quitar bloque roto en backend/__init__.py, si quedó alguno
p = Path("backend/__init__.py")
s = p.read_text(encoding="utf-8")
s2 = re.sub(
    r'\n# === Static frontend routes.*?^except\s+Exception.*?pass\s*$',
    '\n',
    s,
    flags=re.S | re.M
)
if s2 != s:
    p.write_text(s2, encoding="utf-8")
    print("init: bloque estático mal posicionado removido.")
else:
    print("init: sin bloque roto que remover.")

# 2) Inyectar rutas en run.py justo después de crear app = create_app(...)
rp = Path("run.py")
r = rp.read_text(encoding="utf-8")

if "def root_index()" in r or "FRONT_DIR = " in r:
    print("run.py: rutas frontend ya presentes (idempotente).")
else:
    # Localizar la línea de creación de la app
    m = re.search(r'^\s*app\s*=\s*create_app\([^)]*\)\s*$', r, flags=re.M)
    if not m:
        raise SystemExit("No encontré 'app = create_app(...)' en run.py para inyectar rutas.")

    insert_after = m.end()
    block = r"""

# === Static frontend routes (index & JS) — registrado tras crear app ===
try:
    from flask import send_from_directory
    from pathlib import Path as _Path
    # FRONT_DIR relativo a este archivo (raíz del repo)
    FRONT_DIR = (_Path(__file__).resolve().parent / "frontend").resolve()

    @app.route("/", methods=["GET"])
    def root_index():
        return send_from_directory(FRONT_DIR, "index.html")

    @app.route("/js/<path:fname>", methods=["GET"])
    def static_js(fname):
        return send_from_directory(FRONT_DIR / "js", fname)

    @app.route("/favicon.ico", methods=["GET"])
    def favicon_ico():
        p = FRONT_DIR / "favicon.ico"
        if p.exists():
            return send_from_directory(FRONT_DIR, "favicon.ico")
        return ("", 204)
except Exception:
    # Si falta el frontend en el deploy, no romper el API
    pass
"""
    r = r[:insert_after] + block + r[insert_after:]
    rp.write_text(r, encoding="utf-8")
    print("run.py: rutas frontend inyectadas tras create_app().")
PY

echo "➤ Restart local"
pkill -f "python .*run\\.py" 2>/dev/null || true
pkill -f "waitress" 2>/dev/null || true
pkill -f "gunicorn" 2>/dev/null || true
pkill -f "flask" 2>/dev/null || true
sleep 1
nohup python run.py >"$LOG" 2>&1 & disown || true
sleep 2

echo "➤ Smokes"
echo "— GET / (debe 200 y devolver index.html) —"
curl -sS -i http://127.0.0.1:8000/ | sed -n '1,12p'
echo
echo "— GET /js/app.js (debe 200 si existe) —"
curl -sS -i http://127.0.0.1:8000/js/app.js | sed -n '1,10p'
echo

echo "➤ Reglas registradas"
python - <<'PY'
from run import app
with app.app_context():
    for r in app.url_map.iter_rules():
        if r.rule in ("/","/js/<path:fname>","/favicon.ico"):
            print(r.rule, sorted(r.methods), r.endpoint)
PY

echo "➤ Commit & Push"
git add backend/__init__.py run.py || true
git commit -m "fix(web): servir frontend desde run.py (/, /js/*, /favicon.ico) y remover bloque roto de __init__" || true
git push origin main

echo "✓ Listo. Si en Render aún ves 404, redeploy y prueba / y /js/app.js."
