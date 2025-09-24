#!/usr/bin/env bash
set -Eeuo pipefail

INIT="backend/__init__.py"
LOG="${TMPDIR:-/data/data/com.termux/files/usr/tmp}/paste12_server.log"
mkdir -p "$(dirname "$LOG")"

echo "➤ Backup"
cp -f "$INIT" "$INIT.bak.$(date +%s)" 2>/dev/null || true

python - <<'PY'
from pathlib import Path
p = Path("backend/__init__.py")
s = p.read_text(encoding="utf-8")

# Evitar duplicar si ya existe
if "def root_index(" not in s:
    block = r"""

# === Static frontend routes (index & JS) ===
try:
    from flask import send_from_directory
    from pathlib import Path as _Path
    FRONT_DIR = _Path("frontend").resolve()

    @app.route("/", methods=["GET"])
    def root_index():
        # Sirve frontend/index.html
        return send_from_directory(FRONT_DIR, "index.html")

    @app.route("/js/<path:fname>", methods=["GET"])
    def static_js(fname):
        # Sirve archivos JS de frontend/js/
        return send_from_directory(FRONT_DIR / "js", fname)

    @app.route("/favicon.ico", methods=["GET"])
    def favicon_ico():
        p = FRONT_DIR / "favicon.ico"
        if p.exists():
            return send_from_directory(FRONT_DIR, "favicon.ico")
        return ("", 204)
except Exception as _e:
    # No fatal: si falta el frontend, el API sigue vivo
    pass
"""
    if not s.endswith("\n"): s += "\n"
    s += block + "\n"
    p.write_text(s, encoding="utf-8")
    print("init: rutas frontend añadidas.")
else:
    print("init: ya tenía rutas frontend, no se cambia.")
PY

echo "➤ Restart (local)"
pkill -f "python .*run\\.py" 2>/dev/null || true
pkill -f "waitress" 2>/dev/null || true
pkill -f "flask" 2>/dev/null || true
sleep 1
nohup python run.py >"$LOG" 2>&1 & disown || true
sleep 2

BASE="${1:-http://127.0.0.1:8000}"

echo "➤ Smokes"
echo "GET $BASE/ (debe ser 200 text/html)"
curl -sSI "$BASE/" | tr -d '\r' | sed -n '1,10p'
echo
curl -sS "$BASE/" | head -n 10
echo

echo "GET $BASE/js/app.js (debe ser 200 application/javascript)"
curl -sSI "$BASE/js/app.js" | tr -d '\r' | sed -n '1,10p'
echo
curl -sS "$BASE/js/app.js" | head -n 5
echo

echo "➤ Commit (opcional)"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git add backend/__init__.py tools/fix_frontend_404.sh || true
  git commit -m "fix(web): servir frontend en / y /js/app.js desde backend (__init__.py)" || true
fi

echo "✓ Listo. Si en Render aún ves 404 en '/', haz git push y redeploy."
