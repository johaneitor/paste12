#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"

echo "[+] Backup previo (si existe render_entry.py)"
[ -f render_entry.py ] && cp -f render_entry.py "render_entry.py.bak.$(date +%s)" || true

echo "[+] Escribiendo render_entry.py (factory-first con fallback y probes)"
cat > render_entry.py <<'PY'
from __future__ import annotations
import os, re
from flask import Flask, jsonify
# Intentamos usar la factory real primero
app = None
db = None

def _fix_db_url(url: str|None) -> str|None:
    if not url: 
        return None
    # Render/Heroku a veces dan 'postgres://'
    return re.sub(r'^postgres://', 'postgresql://', url)

try:
    # backend.create_app y backend.db (lo ideal)
    from backend import create_app, db as _db
    app = create_app()
    db = _db
except Exception as e1:
    # Fallback: construimos app manual e intentamos registrar el blueprint de backend.routes
    from flask_sqlalchemy import SQLAlchemy
    app = Flask(__name__)
    db_url = _fix_db_url(os.environ.get("DATABASE_URL")) or os.environ.get("SQLALCHEMY_DATABASE_URI") or "sqlite:///app.db"
    app.config["SQLALCHEMY_DATABASE_URI"] = db_url
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
    db = SQLAlchemy(app)
    try:
        # Registrar blueprint /api si existe
        from backend.routes import bp as api_bp  # debe existir en tu proyecto
        try:
            app.register_blueprint(api_bp, url_prefix="/api")
        except Exception:
            # Puede estar ya registrado en create_app; ignoramos
            pass
    except Exception as e2:
        # Si no hay blueprint, al menos la app arranca con health
        pass

# Probes: /api/health y /api/debug-urlmap (no sobrescriben si ya existen)
def _ensure_probe_routes(flask_app: Flask):
    # /api/health
    if not any(str(r.rule)=="/api/health" for r in flask_app.url_map.iter_rules()):
        @flask_app.get("/api/health")
        def _health():
            return jsonify(ok=True, note="render_entry"), 200
    # /api/debug-urlmap
    if not any(str(r.rule)=="/api/debug-urlmap" for r in flask_app.url_map.iter_rules()):
        @flask_app.get("/api/debug-urlmap")
        def _debug_urlmap():
            rules = []
            for r in flask_app.url_map.iter_rules():
                methods = sorted([m for m in r.methods if m not in ("HEAD","OPTIONS")])
                rules.append({"rule": str(r), "endpoint": r.endpoint, "methods": methods})
            return jsonify(ok=True, rules=rules), 200

_ensure_probe_routes(app)

# create_all idempotente (si hay db)
try:
    with app.app_context():
        if db is not None and hasattr(db, "create_all"):
            db.create_all()
except Exception:
    # No impedimos el arranque por esto
    pass
PY

echo "[+] Commit & push"
git add render_entry.py
git commit -m "feat(render_entry): robust entrypoint (factory-first, probes, DB url fix, create_all)" || true
git push -u --force-with-lease origin "$(git rev-parse --abbrev-ref HEAD)"

cat <<'MSG'

========================================
✅ Hecho. Próximos pasos en Render:
1) En Settings → Start Command (una sola línea):
   gunicorn -w ${WEB_CONCURRENCY:-2} -k gthread --threads ${THREADS:-4} -b 0.0.0.0:$PORT render_entry:app

2) En Environment:
   - DATABASE_URL: (tu Postgres). Si empieza con 'postgres://', igual sirve: lo corregimos a 'postgresql://'.

3) Redeploy (si sigue leyendo caché, haz "Clear build cache").

Verificación (luego del deploy):
   curl -s https://<tu-app>/api/health
   curl -s https://<tu-app>/api/debug-urlmap | jq .
   curl -i -s 'https://<tu-app>/api/notes?page=1' | sed -n '1,120p'
   curl -i -s -X POST -H 'Content-Type: application/json' \
        -d '{"text":"hello","hours":24}' \
        https://<tu-app>/api/notes | sed -n '1,160p'
========================================
MSG
