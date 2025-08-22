#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
cd "${1:-$(pwd)}"

LOG=".tmp/paste12.log"

backup(){ [ -f run.py ] && cp run.py "run.py.bak.$(date +%s)" || true; }

backup
cat > run.py <<'PY'
from __future__ import annotations

import os
import logging
from flask import Flask, send_from_directory

# Import del blueprint de la API
try:
    from backend.routes import bp as api_bp  # bp = Blueprint("api", __name__)
except Exception as e:
    api_bp = None
    logging.getLogger("run").error("No pude importar backend.routes: %s", e)

app = Flask(__name__, static_folder="public", static_url_path="")

# Rutas estáticas básicas (compatibles con lo que ya tenías)
@app.route("/")
def static_root():
    index_path = os.path.join(app.static_folder, "index.html")
    if os.path.exists(index_path):
        return send_from_directory(app.static_folder, "index.html")
    return "", 200

@app.route("/<path:filename>")
def static(filename: str):
    return send_from_directory(app.static_folder, filename)

@app.route("/ads.txt")
def static_ads():
    return send_from_directory(app.static_folder, "ads.txt")

@app.route("/favicon.ico")
def static_favicon():
    return send_from_directory(app.static_folder, "favicon.ico")

# Silenciar warning del rate limiter si no hay backend
try:
    if "RATELIMIT_STORAGE_URI" not in app.config:
        app.config["RATELIMIT_STORAGE_URI"] = os.environ.get("RATELIMIT_STORAGE_URI", "memory://")
except Exception:
    pass

# Registrar blueprint /api solo una vez
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

# Verificación rápida de sintaxis
python -m py_compile run.py

# Reiniciar app y probar
pkill -f "python .*run.py" 2>/dev/null || true
: > "$LOG" || true
nohup python run.py >"$LOG" 2>&1 &
sleep 2

echo "[+] Tail de logs:"
tail -n 40 "$LOG" || true

echo "[+] URL map (resumen):"
python - <<'PY'
import importlib
mod = importlib.import_module("run")
app = mod.app
for r in sorted(app.url_map.iter_rules(), key=lambda x: str(x)):
    methods = ",".join(sorted(m for m in r.methods if m not in ("HEAD","OPTIONS")))
    print(f"{str(r):35s} {methods:8s} {r.endpoint}")
PY

PORT=$(grep -Eo '127\.0\.0\.1:[0-9]+' "$LOG" | tail -n1 | cut -d: -f2 || echo 8000)

echo "[+] Smoke GET /api/notes"
curl -i -s "http://127.0.0.1:$PORT/api/notes?page=1" | sed -n '1,40p'
echo
echo "[+] Smoke POST /api/notes"
curl -i -s -X POST -H "Content-Type: application/json" \
  -d '{"text":"smoke-from-repair","hours":24}' \
  "http://127.0.0.1:$PORT/api/notes" | sed -n '1,100p'
echo
