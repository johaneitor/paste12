#!/usr/bin/env bash
set -Eeuo pipefail

WEBUI="backend/webui.py"
LOG="${TMPDIR:-/data/data/com.termux/files/usr/tmp}/paste12_server.log"
mkdir -p "$(dirname "$LOG")"

echo "➤ Backup"
cp -f "$WEBUI" "$WEBUI.bak.$(date +%s)" 2>/dev/null || true

echo "➤ Copiar frontend -> backend/frontend (sin borrar el original)"
mkdir -p backend/frontend
# usa rsync si está, si no cp -a
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete frontend/ backend/frontend/
else
  (cd frontend && tar cf - .) | (cd backend/frontend && tar xpf -)
fi

echo "➤ Parchear backend/webui.py para buscar en varias ubicaciones"
python - <<'PY'
from pathlib import Path
p = Path("backend/webui.py")
code = (
    "from flask import Blueprint, send_from_directory\n"
    "from pathlib import Path\n"
    "# Detecta dónde está el frontend (soporta deploy con root en 'backend')\n"
    "PKG_DIR = Path(__file__).resolve().parent  # .../backend\n"
    "CANDIDATES = [\n"
    "    PKG_DIR / 'frontend',                 # backend/frontend (subdir deploy)\n"
    "    PKG_DIR.parent / 'frontend',          # <repo>/frontend (root deploy)\n"
    "    Path.cwd() / 'frontend',              # fallback\n"
    "]\n"
    "for _cand in CANDIDATES:\n"
    "    if _cand.exists():\n"
    "        FRONT_DIR = _cand\n"
    "        break\n"
    "else:\n"
    "    FRONT_DIR = CANDIDATES[0]\n"
    "webui = Blueprint('webui', __name__)\n\n"
    "@webui.route('/', methods=['GET'])\n"
    "def index():\n"
    "    return send_from_directory(FRONT_DIR, 'index.html')\n\n"
    "@webui.route('/js/<path:fname>', methods=['GET'])\n"
    "def js(fname):\n"
    "    return send_from_directory(FRONT_DIR / 'js', fname)\n\n"
    "@webui.route('/favicon.ico', methods=['GET'])\n"
    "def favicon():\n"
    "    p = FRONT_DIR / 'favicon.ico'\n"
    "    if p.exists():\n"
    "        return send_from_directory(FRONT_DIR, 'favicon.ico')\n"
    "    return ('', 204)\n"
)
p.write_text(code, encoding="utf-8")
print("webui.py actualizado con búsqueda de rutas múltiples.")
PY

echo "➤ Restart local rápido para probar"
pkill -f "python .*run\\.py" 2>/dev/null || true
pkill -f waitress 2>/dev/null || true
pkill -f gunicorn 2>/dev/null || true
pkill -f flask 2>/dev/null || true
sleep 1
nohup python run.py >"$LOG" 2>&1 & disown || true
sleep 2

echo "➤ Smokes locales"
echo "— / —"
curl -sS -i http://127.0.0.1:8000/ | sed -n '1,12p'
echo
echo "— /js/app.js —"
curl -sS -i http://127.0.0.1:8000/js/app.js | sed -n '1,12p'
echo

echo "➤ Commit & Push"
git add backend/webui.py backend/frontend || true
git commit -m "fix(web): servir frontend desde backend/frontend y fallback a varias rutas (Render subdir compatible)" || true
git push origin main || true

echo "✓ Listo. En Render, con start command 'gunicorn -w 4 -k gthread -b 0.0.0.0:$PORT backend:app', / y /js/app.js deben dar 200."
