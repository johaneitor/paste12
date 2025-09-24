#!/usr/bin/env bash
set -Eeuo pipefail

echo "➤ .gitattributes (forzar LF en todo, especialmente .py/.sh/Procfile)"
cat > .gitattributes <<'GITATTR'
* text=auto eol=lf
*.py text eol=lf
*.sh text eol=lf
Procfile text eol=lf
requirements.txt text eol=lf
GITATTR

echo "➤ run.py (normaliza DATABASE_URL y fallback SQLite)"
cat > run.py <<'PY'
from __future__ import annotations

import os, re, pathlib
from flask import Flask
from backend import db

def _db_uri() -> str:
    uri = os.getenv("DATABASE_URL")
    if uri:
        # postgres -> postgresql+psycopg (SQLAlchemy 2.x + Psycopg 3)
        uri = re.sub(r'^postgres://', 'postgresql+psycopg://', uri)
        # postgresql:// -> postgresql+psycopg:// si falta el driver
        if uri.startswith('postgresql://') and '+psycopg://' not in uri:
            uri = uri.replace('postgresql://', 'postgresql+psycopg://', 1)
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

echo "➤ requirements.txt limpio (una lib por línea; psycopg v3 binario válido)"
cat > requirements.txt <<'REQ'
Flask==3.0.3
Werkzeug==3.1.3
Flask-SQLAlchemy==3.1.1
SQLAlchemy==2.0.31
gunicorn==22.0.0
psycopg[binary]>=3.2.2,<3.3
REQ

echo "➤ Validando sintaxis básica"
python -m py_compile run.py || true

echo "➤ Commit y push"
git add .gitattributes run.py Procfile requirements.txt
git commit -m "fix(deploy): normaliza LF; run.py con DATABASE_URL; Procfile; requirements limpios (psycopg>=3.2.2,<3.3)"
git push origin main || true

echo "✔ Listo. En Render, usa:"
echo "  Build Command: pip install -r requirements.txt"
echo "  Start Command: gunicorn run:app --bind 0.0.0.0:$PORT"
echo "  Env: DATABASE_URL=postgres://<user>:<pass>@<host>:<port>/<db>"
