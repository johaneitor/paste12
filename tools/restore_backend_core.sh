#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"
mkdir -p .tmp

stamp(){ date +%Y%m%d-%H%M%S; }

# --- backend/__init__.py con db y limiter ---
[ -f backend/__init__.py ] && cp backend/__init__.py "backend/__init__.py.bak.$(stamp)"
cat > backend/__init__.py <<'PY'
from __future__ import annotations
import os
from flask_sqlalchemy import SQLAlchemy
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address

# Objetos de extensión exportados por el paquete
db = SQLAlchemy()
limiter = Limiter(key_func=get_remote_address, default_limits=[])

def init_extensions(app):
    # Config mínima de DB y Limiter
    app.config.setdefault("SQLALCHEMY_DATABASE_URI", os.environ.get("DATABASE_URL", "sqlite:///app.db"))
    app.config.setdefault("SQLALCHEMY_TRACK_MODIFICATIONS", False)
    app.config.setdefault("RATELIMIT_STORAGE_URI", os.environ.get("RATELIMIT_STORAGE_URI", "memory://"))
    # Inicializar extensiones
    db.init_app(app)
    limiter.init_app(app)
PY

# --- run.py: asegurar init_extensions() y create_all() ANTES de registrar blueprint ---
[ -f run.py ] && cp run.py "run.py.bak.$(stamp)"
cat > run.py <<'PY'
from __future__ import annotations

import os
from flask import Flask, jsonify, send_from_directory
from backend import init_extensions, db

app = Flask(__name__, static_folder="public", static_url_path="")

# Inicializar extensiones (db, limiter, etc.)
init_extensions(app)

# Cargar modelos para que create_all conozca las tablas
try:
    import backend.models  # noqa: F401
except Exception as e:
    try:
        app.logger.error("Error importando modelos: %r", e)
    except Exception:
        pass

# Crear tablas si no existen (no rompe si ya existen)
try:
    with app.app_context():
        db.create_all()
except Exception as e:
    try:
        app.logger.error("Error en create_all: %r", e)
    except Exception:
        pass

# Registrar blueprint API (si existe)
try:
    from backend.routes import bp as api_bp
    if api_bp.name not in app.blueprints:
        app.register_blueprint(api_bp, url_prefix="/api")
except Exception as e:
    try:
        app.logger.error("No se pudo registrar blueprint API: %r", e)
    except Exception:
        pass

@app.route("/")
def static_root():
    idx = os.path.join(app.static_folder or "", "index.html")
    if idx and os.path.exists(idx):
        return send_from_directory(app.static_folder, "index.html")
    return jsonify({"ok": True})

@app.route("/ads.txt")
def static_ads():
    p = os.path.join(app.static_folder or "", "ads.txt")
    if p and os.path.exists(p):
        return send_from_directory(app.static_folder, "ads.txt")
    return ("", 404)

@app.route("/favicon.ico")
def static_favicon():
    p = os.path.join(app.static_folder or "", "favicon.ico")
    if p and os.path.exists(p):
        return send_from_directory(app.static_folder, "favicon.ico")
    return ("", 404)

if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8000"))
    host = os.environ.get("HOST", "0.0.0.0")
    app.run(host=host, port=port)
PY

# --- Compilar para chequear sintaxis ---
python -m py_compile backend/__init__.py run.py backend/*.py backend/**/*.py || true

# --- Reiniciar y humos ---
LOG=".tmp/paste12.log"
pkill -f "python .*run.py" 2>/dev/null || true
: > "$LOG" || true
nohup python run.py >"$LOG" 2>&1 &
sleep 2

echo "[+] URL map:"
python - <<'PY' 2>/dev/null || true
import importlib
app = importlib.import_module("run").app
for r in sorted(app.url_map.iter_rules(), key=lambda x: (str(x), sorted(x.methods))):
    m = ",".join(sorted([i for i in r.methods if i not in ("HEAD","OPTIONS")]))
    print(f"{r.rule:35s} {m:10s} {r.endpoint}")
print()
print("HAS /api/notes GET:", any(r.rule=="/api/notes" and "GET" in r.methods for r in app.url_map.iter_rules()))
print("HAS /api/notes POST:", any(r.rule=="/api/notes" and "POST" in r.methods for r in app.url_map.iter_rules()))
PY

PORT="$(grep -Eo '127\.0\.0\.1:[0-9]+' "$LOG" | tail -n1 | cut -d: -f2 || echo 8000)"
echo "[i] PORT_LOCAL=$PORT"

echo "[+] Smoke GET /api/notes"
curl -s -i "http://127.0.0.1:$PORT/api/notes?page=1" | sed -n '1,60p'
echo
echo "[+] Smoke POST /api/notes"
curl -s -i -X POST -H "Content-Type: application/json" \
  -d '{"text":"restore-core","hours":24}' "http://127.0.0.1:$PORT/api/notes" | sed -n '1,120p'
echo
echo "[+] Tail logs:"
tail -n 80 "$LOG" || true
