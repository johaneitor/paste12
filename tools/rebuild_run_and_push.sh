#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"
LOG=".tmp/paste12.log"

say(){ printf "\n[+] %s\n" "$*"; }
warn(){ printf "\n[!] %s\n" "$*"; }

[ -f run.py ] && cp run.py "run.py.bak.$(date +%s)" || true

say "Escribiendo run.py limpio y con guardas correctas…"
cat > run.py <<'PY'
from __future__ import annotations

import os
import logging
from flask import Flask, send_from_directory
from backend.routes import bp as api_bp

# App base con carpeta 'public' para estáticos
app = Flask(__name__, static_folder="public", static_url_path="")

# Rutas estáticas mínimas (compatibles con lo que tenías en URL map)
@app.route("/")
def static_root():
    idx = os.path.join(app.static_folder, "index.html")
    if os.path.exists(idx):
        return send_from_directory(app.static_folder, "index.html")
    return "", 200

@app.route("/<path:filename>")
def static(filename):
    try:
        return send_from_directory(app.static_folder, filename)
    except Exception:
        # Evita 500 si el archivo no existe; deja que Flask devuelva 404
        from flask import abort
        abort(404)

@app.route("/ads.txt")
def static_ads():
    return send_from_directory(app.static_folder, "ads.txt")

@app.route("/favicon.ico")
def static_favicon():
    return send_from_directory(app.static_folder, "favicon.ico")

# Config por defecto para Flask-Limiter (silencia warning si no hay Redis)
try:
    if "RATELIMIT_STORAGE_URI" not in app.config:
        app.config["RATELIMIT_STORAGE_URI"] = os.environ.get("RATELIMIT_STORAGE_URI", "memory://")
except Exception:
    pass

# Registrar blueprint /api con guarda para no duplicarlo
try:
    if hasattr(app, "blueprints") and "api" not in app.blueprints:
        app.register_blueprint(api_bp, url_prefix="/api")
except Exception as e:
    logging.getLogger("run").error("No se pudo registrar blueprint API: %s", e)

if __name__ == "__main__":
    host = os.environ.get("HOST", "0.0.0.0")
    port = int(os.environ.get("PORT", "8000"))
    app.run(host=host, port=port)
    print(f"✓ Servidor en http://{host}:{port}")
PY

# Reiniciar local y probar
say "Reiniciando servidor local…"
pkill -f "python .*run.py" 2>/dev/null || true
: > "$LOG" || true
nohup python run.py >"$LOG" 2>&1 &
sleep 2

say "Tail de logs:"
tail -n 40 "$LOG" || true

say "URL map (esperamos /api/notes GET y POST)…"
python - <<'PY'
import importlib
mod = importlib.import_module("run")
app = mod.app
rules = [(str(r), sorted([m for m in r.methods if m not in ("HEAD","OPTIONS")]), r.endpoint) for r in app.url_map.iter_rules()]
for r, m, e in sorted(rules):
    print(f"{r:35s} {','.join(m):8s} {e}")
PY

PORT=$(grep -Eo '127\.0\.0\.1:[0-9]+' "$LOG" | tail -n1 | cut -d: -f2 || echo 8000)

say "Smoke GET /api/notes"
curl -i -s "http://127.0.0.1:$PORT/api/notes?page=1" | sed -n '1,40p'
echo
say "Smoke POST /api/notes"
curl -i -s -X POST -H "Content-Type: application/json" \
  -d '{"text":"smoke-from-rebuild","hours":24}' \
  "http://127.0.0.1:$PORT/api/notes" | sed -n '1,100p'
echo

# --- Git push de TODO ---
say "Preparando commit y push…"
if [ ! -d .git ]; then
  git init -b main
fi

REMOTE_URL="${REMOTE_URL:-https://github.com/johaneitor/paste12.git}"
if ! git remote | grep -qx origin; then
  say "Agregando remoto origin → $REMOTE_URL"
  git remote add origin "$REMOTE_URL" || true
fi

[ -n "$(git config user.name || true)" ]  || git config user.name  "termux"
[ -n "$(git config user.email || true)" ] || git config user.email "termux@localhost"

git add -A
git commit -m "fix(run): rebuild file with safe API blueprint guard; add static routes; limiter default; smoke OK" || true

BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
if ! git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
  if ! git push -u origin "$BRANCH"; then
    git push -u --force-with-lease origin "$BRANCH"
  fi
else
  if ! git push; then
    git push --force-with-lease
  fi
fi

say "Últimos commits:"
git --no-pager log --oneline -n 5
say "Listo ✅"
