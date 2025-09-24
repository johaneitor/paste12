#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
cd "${1:-$(pwd)}"

LOG=".tmp/paste12.log"

echo "[+] Backup de run.py"
[ -f run.py ] && cp run.py "run.py.bak.$(date +%s)" || true

echo "[+] Escribiendo run.py limpio (sin endpoint 'static')…"
cat > run.py <<'PY'
from __future__ import annotations

import os
import logging
from flask import Flask, send_from_directory, abort

# Desactiva auto-static para evitar el endpoint 'static'
app = Flask(__name__, static_folder="public", static_url_path=None)

# Import del blueprint de la API
api_bp = None
try:
    from backend.routes import bp as api_bp  # bp = Blueprint("api", __name__)
except Exception as e:
    logging.getLogger("run").error("No pude importar backend.routes: %s", e)

# Endpoints estáticos con nombres únicos (no 'static')
@app.get("/", endpoint="root_index")
def root_index():
    idx = os.path.join(app.static_folder, "index.html")
    if os.path.exists(idx):
        return send_from_directory(app.static_folder, "index.html")
    return "", 200

@app.get("/favicon.ico", endpoint="favicon_file")
def favicon_file():
    path = os.path.join(app.static_folder, "favicon.ico")
    if os.path.exists(path):
        return send_from_directory(app.static_folder, "favicon.ico")
    abort(404)

@app.get("/ads.txt", endpoint="ads_txt_file")
def ads_txt_file():
    path = os.path.join(app.static_folder, "ads.txt")
    if os.path.exists(path):
        return send_from_directory(app.static_folder, "ads.txt")
    abort(404)

@app.get("/<path:filename>", endpoint="public_file")
def public_file(filename: str):
    path = os.path.join(app.static_folder, filename)
    if os.path.isdir(path) or not os.path.exists(path):
        abort(404)
    return send_from_directory(app.static_folder, filename)

# Limiter storage por defecto (silencia warning)
try:
    if "RATELIMIT_STORAGE_URI" not in app.config:
        app.config["RATELIMIT_STORAGE_URI"] = os.environ.get("RATELIMIT_STORAGE_URI", "memory://")
except Exception:
    pass

# Registrar blueprint /api solo si aún no está
try:
    if api_bp is not None and "api" not in app.blueprints:
        app.register_blueprint(api_bp, url_prefix="/api")
except Exception as e:
    logging.getLogger("run").error("No se pudo registrar blueprint API: %s", e)

if __name__ == "__main__":
    host = os.environ.get("HOST", "0.0.0.0")
    port = int(os.environ.get("PORT", "8000"))
    app.run(host=host, port=port)
    print(f"✓ Servidor en http://{host}:{port}")
PY

echo "[+] Verificando sintaxis"
python -m py_compile run.py

echo "[+] Reiniciando servidor local…"
pkill -f "python .*run.py" 2>/dev/null || true
: > "$LOG" || true
nohup python run.py >"$LOG" 2>&1 &
sleep 2

echo "[+] Tail de logs:"
tail -n 50 "$LOG" || true

echo "[+] URL map:"
python - <<'PY'
import importlib
app = importlib.import_module("run").app
for r in sorted(app.url_map.iter_rules(), key=lambda x: str(x)):
    methods = ",".join(sorted(m for m in r.methods if m not in ("HEAD","OPTIONS")))
    print(f"{str(r):35s} {methods:8s} {r.endpoint}")
PY

PORT=$(grep -Eo '127\.0\.0\.1:[0-9]+' "$LOG" | tail -n1 | cut -d: -f2 || echo 8000)

echo "[+] Smoke GET /api/notes"
curl -i -s "http://127.0.0.1:$PORT/api/notes?page=1" | sed -n '1,60p'
echo
echo "[+] Smoke POST /api/notes"
curl -i -s -X POST -H "Content-Type: application/json" \
  -d '{"text":"run-fix-smoke","hours":24}' \
  "http://127.0.0.1:$PORT/api/notes" | sed -n '1,120p'
echo

# Commit & push (opcional)
if [ -d .git ]; then
  BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
  git add -A
  git commit -m "fix(run): disable auto static; custom static endpoints; safe /api blueprint register" || true
  git push -u --force-with-lease origin "$BRANCH" || echo "[!] Push falló (revisa red/credenciales)."
fi
