#!/usr/bin/env bash
set -Eeuo pipefail

echo "➤ Backups"
cp -f backend/__init__.py "backend/__init__.py.bak.$(date +%s)" 2>/dev/null || true
cp -f run.py "run.py.bak.$(date +%s)" 2>/dev/null || true
[ -f Procfile ] && cp -f Procfile "Procfile.bak.$(date +%s)" || true

echo "➤ backend/__init__.py: agrega create_app() y normaliza DATABASE_URL"
cat > backend/__init__.py <<'PY'
from __future__ import annotations

from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()

def _db_uri() -> str:
    import os, re, pathlib
    uri = os.getenv("DATABASE_URL")
    if uri:
        # postgres -> postgresql+psycopg
        uri = re.sub(r"^postgres://", "postgresql+psycopg://", uri)
        # postgresql:// -> postgresql+psycopg:// si falta driver
        if uri.startswith("postgresql://") and "+psycopg://" not in uri:
            uri = uri.replace("postgresql://", "postgresql+psycopg://", 1)
        return uri
    # Fallback SQLite local
    db_path = pathlib.Path("data/app.db").resolve()
    return f"sqlite:///{db_path}"

def create_app():
    from flask import Flask
    app = Flask(__name__)
    app.config["SQLALCHEMY_DATABASE_URI"] = _db_uri()
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
    app.config["SQLALCHEMY_ENGINE_OPTIONS"] = {
        "pool_pre_ping": True,
        "pool_recycle": 280,
    }
    db.init_app(app)

    # Registrar blueprint después de init_app para evitar ciclos
    from .routes import api as api_blueprint  # import diferido
    app.register_blueprint(api_blueprint)

    # Crear tablas si no existen
    with app.app_context():
        db.create_all()

    return app
PY

echo "➤ run.py: usar create_app()"
cat > run.py <<'PY'
from __future__ import annotations
import os
from backend import create_app

app = create_app()

if __name__ == "__main__":
    host = os.getenv("HOST", "0.0.0.0")
    port = int(os.getenv("PORT", "8000"))
    app.run(host=host, port=port)
PY

echo "➤ Procfile: usar la factory en producción"
cat > Procfile <<'PF'
web: gunicorn "backend:create_app()" --bind 0.0.0.0:$PORT --workers=${WEB_CONCURRENCY:-2} --threads=${WEB_THREADS:-4} --timeout 120
PF

echo "➤ Validando sintaxis"
python -m py_compile backend/__init__.py run.py || true

echo "➤ Smoke local rápido"
pkill -f "python .*run\.py" 2>/dev/null || true
sleep 1
nohup python run.py >/dev/null 2>&1 & disown || true
sleep 2
echo "health=$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/api/health)"
echo "notes_get=$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/api/notes)"

echo "➤ Commit & push"
git add backend/__init__.py run.py Procfile
git commit -m "feat(app-factory): añade backend.create_app() y unifica arranque (gunicorn factory / run.py)"
git push origin main || true
