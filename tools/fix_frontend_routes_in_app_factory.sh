#!/usr/bin/env bash
set -Eeuo pipefail

INIT="backend/__init__.py"
LOG="${TMPDIR:-/data/data/com.termux/files/usr/tmp}/paste12_server.log"
mkdir -p "$(dirname "$LOG")"

echo "➤ Backup"
cp -f "$INIT" "$INIT.bak.$(date +%s)" 2>/dev/null || true

python - <<'PY'
from pathlib import Path
import re

p = Path("backend/__init__.py")
s = p.read_text(encoding="utf-8")

# 1) Quitar cualquier bloque viejo mal posicionado (el que empieza con el comentario)
s = re.sub(
    r'\n# === Static frontend routes.*?^except\s+Exception.*?pass\s*$',
    '\n',
    s,
    flags=re.S | re.M
)

# 2) Insertar rutas estáticas DENTRO de create_app, justo antes de "return app"
inject = r"""
    # === Static frontend routes (index & JS) — dentro de create_app ===
    try:
        from flask import send_from_directory
        from pathlib import Path as _Path
        _PKG_DIR = _Path(__file__).resolve().parent     # .../backend
        FRONT_DIR = (_PKG_DIR.parent / "frontend").resolve()

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
        # Si no hay frontend en el deploy, no romper el API
        pass
"""

# Ubicar el primer 'return app' de la función create_app
m = re.search(r'(def\s+create_app\s*\([^)]*\)\s*:\s*[\s\S]*?)\n(\s*)return\s+app\b', s)
if not m:
    raise SystemExit("No pude localizar create_app(...) y su 'return app' para inyectar rutas.")
head = s[:m.start(2)]
indent = m.group(2)
tail = s[m.start(2):]

# Asegurar indentación correcta del bloque inyectado (4 espacios por nivel)
block = "\n".join((indent + line if line.strip() else line) for line in inject.splitlines())

s_new = head + block + "\n" + tail

if s_new == s:
    print("init: sin cambios (posiblemente ya estaba correctamente insertado).")
else:
    p.write_text(s_new, encoding="utf-8")
    print("init: rutas frontend insertadas dentro de create_app.")
PY

echo "➤ Restart local"
pkill -f "python .*run\\.py" 2>/dev/null || true
pkill -f "waitress" 2>/dev/null || true
pkill -f "gunicorn" 2>/dev/null || true
pkill -f "flask" 2>/dev/null || true
sleep 1
nohup python run.py >"$LOG" 2>&1 & disown || true
sleep 2

echo "➤ Smoke / y /js/app.js"
curl -sS -i http://127.0.0.1:8000/ | sed -n '1,15p'
echo
curl -sS -i http://127.0.0.1:8000/js/app.js | sed -n '1,10p'

echo "➤ Commit & Push"
git add backend/__init__.py || true
git commit -m "fix(web): registrar rutas frontend dentro de create_app y resolver FRONT_DIR relativo al paquete" || true
git push origin main

echo "✓ Listo."
