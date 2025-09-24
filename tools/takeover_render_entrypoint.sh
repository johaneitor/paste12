#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"
RENDER_URL="${RENDER_URL:-https://paste12-rmsk.onrender.com}"

echo "[+] Backups de posibles entrypoints"
for f in wsgi.py wsgiapp.py wsgi_app.py app.py; do
  [ -f "$f" ] && cp -f "$f" "$f.bak.$(date +%s)" || true
done

echo "[+] Aseguro app.py exportando la app y salud con marca 'triplex'"
cat > app.py <<'PY'
from __future__ import annotations
import os
from flask import Flask, jsonify
from backend import create_app, db

VER = "triplex-v2"

def _has_rule(app, rule: str, method: str) -> bool:
    try:
        for r in app.url_map.iter_rules():
            if str(r) == rule and method.upper() in r.methods:
                return True
    except Exception:
        pass
    return False

app: Flask = create_app()

# Registrar /api/notes si faltara (idempotente)
try:
    from backend.routes_notes import register_api
    if not (_has_rule(app, "/api/notes", "GET") and _has_rule(app, "/api/notes", "POST")):
        register_api(app)
except Exception:
    pass

# Health con marca
if not _has_rule(app, "/api/health", "GET"):
    @app.get("/api/health")
    def _health():
        ok_api = _has_rule(app, "/api/notes", "GET") and _has_rule(app, "/api/notes", "POST")
        return jsonify(ok=True, note="triplex", ver=VER, api=ok_api)

# create_all no falla si ya existen tablas
try:
    with app.app_context():
        db.create_all()
except Exception:
    pass

if __name__ == "__main__":
    host = os.environ.get("HOST", "0.0.0.0")
    port = int(os.environ.get("PORT", "8000"))
    app.run(host=host, port=port)
PY

echo "[+] Fuerzo TODOS los nombres típicos de entrypoint a reexportar la misma app"
cat > wsgi.py <<'PY'
from app import app  # Render: gunicorn wsgi:app
PY
cat > wsgiapp.py <<'PY'
from app import app  # Por si el Start Command apunta a 'wsgiapp:app'
PY
cat > wsgi_app.py <<'PY'
from app import app  # Otra variante común
PY

echo "[+] Commit & push"
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
git add -A
git commit -m "render: force entrypoint takeover (wsgi*, app.py) and health marker 'triplex-v2'" || true
git push -u --force-with-lease origin "$BRANCH"

echo "[i] Esperando 15s a que Render redeploye…"
sleep 15

echo "[+] Verificando remoto /api/health"
curl -s "$RENDER_URL/api/health" || true
echo
echo "[+] GET /api/notes"
curl -i -s "$RENDER_URL/api/notes?page=1" | sed -n '1,80p'
echo
echo "[+] POST /api/notes"
curl -i -s -X POST -H "Content-Type: application/json" \
  -d '{"text":"remote-takeover","hours":24}' \
  "$RENDER_URL/api/notes" | sed -n '1,120p'
echo
echo "[i] Si /api/health NO muestra note=triplex, abre Render > Service > Start Command y pon:"
echo "    gunicorn wsgi:app"
echo "    (o prueba 'gunicorn wsgiapp:app' si el anterior no aplica). Guarda y redeploy."
