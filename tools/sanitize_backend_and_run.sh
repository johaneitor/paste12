#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"
mkdir -p .tmp

stamp(){ date +%Y%m%d-%H%M%S; }

# --- 1) backend/__init__.py: stub seguro para evitar IndentationError ---
if [ -f backend/__init__.py ]; then
  cp backend/__init__.py "backend/__init__.py.bak.$(stamp)"
fi
cat > backend/__init__.py <<'PY'
# backend package init (sanitized)
# Si antes tenías lógica aquí, quedó respaldada en backend/__init__.py.bak.TIMESTAMP
__all__ = []
PY

# --- 2) run.py limpio y con guardas correctas ---
if [ -f run.py ]; then
  cp run.py "run.py.bak.$(stamp)"
fi
cat > run.py <<'PY'
from __future__ import annotations

import os
from flask import Flask, jsonify, send_from_directory

# App con estáticos en ./public (sin colisionar endpoint 'static')
app = Flask(__name__, static_folder="public", static_url_path="")

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

# Registrar blueprint API si existe y no está ya registrado
try:
    from backend.routes import bp as api_bp  # backend.routes a su vez importa backend.routes_notes
    if api_bp.name not in app.blueprints:
        app.register_blueprint(api_bp, url_prefix="/api")
except Exception as e:
    # No rompemos el arranque por esto; quedará visible en logs
    try:
        app.logger.error("No se pudo registrar blueprint API: %r", e)
    except Exception:
        pass

if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8000"))
    host = os.environ.get("HOST", "0.0.0.0")
    app.run(host=host, port=port)
PY

# --- 3) Compilar para detectar cualquier error sintáctico inmediatamente ---
echo "[+] Compilando módulos…"
python -m py_compile run.py backend/*.py backend/**/*.py || true

# --- 4) Reiniciar app local ---
LOG=".tmp/paste12.log"
pkill -f "python .*run.py" 2>/dev/null || true
: > "$LOG" || true
nohup python run.py >"$LOG" 2>&1 &
sleep 2

# --- 5) URL map y humos de /api/notes ---
echo "[+] URL map (resumen):"
python - <<'PY' 2>/dev/null || true
import importlib
mod = importlib.import_module("run")
app = mod.app
for r in sorted(app.url_map.iter_rules(), key=lambda x: (str(x), sorted(x.methods))):
    meth = ",".join(sorted([m for m in r.methods if m not in ("HEAD","OPTIONS")]))
    print(f"{r.rule:35s} {meth:10s} {r.endpoint}")
print()
has_get = any(r.rule=="/api/notes" and "GET" in r.methods for r in app.url_map.iter_rules())
has_post= any(r.rule=="/api/notes" and "POST" in r.methods for r in app.url_map.iter_rules())
print(f"/api/notes GET:{has_get} POST:{has_post}")
PY

PORT="$(grep -Eo '127\.0\.0\.1:[0-9]+' "$LOG" | tail -n1 | cut -d: -f2 || echo 8000)"
echo "[i] PORT_LOCAL=$PORT"

echo "[+] Smoke GET /api/notes"
curl -s -i "http://127.0.0.1:$PORT/api/notes?page=1" | sed -n '1,40p'
echo
echo "[+] Smoke POST /api/notes"
curl -s -i -X POST -H "Content-Type: application/json" \
  -d '{"text":"sanity-post","hours":24}' \
  "http://127.0.0.1:$PORT/api/notes" | sed -n '1,120p'
echo
echo "[+] Tail logs:"
tail -n 60 "$LOG" || true
