#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(pwd)"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
LOG="${PREFIX}/tmp/paste12_server.log"
mkdir -p "$(dirname "$LOG")" data

echo "➤ Backups"
cp -f run.py "run.py.bak.$(date +%s)" 2>/dev/null || true

echo "➤ run.py: usar DATABASE_URL si existe (fallback SQLite)"
cat > run.py <<'PY'
from __future__ import annotations

import os, re, pathlib
from flask import Flask
from backend import db

def _db_uri() -> str:
    uri = os.getenv("DATABASE_URL")
    if uri:
        # Normalizar esquema postgres -> postgresql+psycopg
        uri = re.sub(r'^postgres://', 'postgresql+psycopg://', uri)
        return uri
    # Fallback SQLite local
    db_path = pathlib.Path('data/app.db').resolve()
    return f"sqlite:///{db_path}"

app = Flask(__name__)
app.config["SQLALCHEMY_DATABASE_URI"] = _db_uri()
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
app.config["SQLALCHEMY_ENGINE_OPTIONS"] = {
    "pool_pre_ping": True,
    "pool_recycle": 280,
}

db.init_app(app)

from backend.routes import api as api_blueprint  # noqa: E402
app.register_blueprint(api_blueprint)

with app.app_context():
    # create_all para entornos sin migraciones; en Postgres no hace daño si ya existen
    db.create_all()

if __name__ == "__main__":
    host = os.getenv("HOST", "0.0.0.0")
    port = int(os.getenv("PORT", "8000"))
    app.run(host=host, port=port)
PY

echo "➤ Procfile (Gunicorn)"
cat > Procfile <<'PF'
web: gunicorn run:app --bind 0.0.0.0:$PORT --workers=${WEB_CONCURRENCY:-2} --threads=${WEB_THREADS:-4} --timeout 120
PF

echo "➤ requirements.txt (mínimos)"
cat > requirements.txt <<'REQ'
Flask==3.0.3
Werkzeug==3.1.3
Flask-SQLAlchemy==3.1.1
SQLAlchemy==2.0.31
gunicorn==22.0.0
psycopg[binary]==3.2.1
REQ

echo "➤ runtime.txt (Heroku opcional)"
cat > runtime.txt <<'RT'
python-3.12.11
RT

echo "➤ Smoke local (Flask dev)"
pkill -f "python .*run\.py" 2>/dev/null || true
sleep 1
nohup python run.py >"$LOG" 2>&1 & disown || true
sleep 2
echo "health=$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/api/health)"
echo "notes_get=$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/api/notes)"

echo "➤ Commit & push"
git add run.py Procfile requirements.txt runtime.txt
git commit -m "chore(deploy): Procfile+requirements; run.py lee DATABASE_URL (fallback SQLite); engine keepalive"
git push origin main || true

echo "✔ Listo. En tu plataforma, definí env DATABASE_URL si usás Postgres."
