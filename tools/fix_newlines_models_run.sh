#!/usr/bin/env bash
set -Eeuo pipefail
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
LOG="${PREFIX}/tmp/paste12_server.log"
DBURI="sqlite:////data/data/com.termux/files/home/paste12/data/app.db"

# Backups
cp -f backend/models.py "backend/models.py.bak.$(date +%s)" 2>/dev/null || true
cp -f run.py "run.py.bak.$(date +%s)" 2>/dev/null || true

# models.py limpio (con índice en línea separada)
cat > backend/models.py <<'PY'
from __future__ import annotations

from datetime import datetime
from sqlalchemy import Index
from backend import db

class Note(db.Model):
    __tablename__ = "notes"
    id         = db.Column(db.Integer, primary_key=True)
    text       = db.Column(db.Text, nullable=False)
    timestamp  = db.Column(db.DateTime, default=datetime.utcnow, nullable=False, index=True)
    expires_at = db.Column(db.DateTime, nullable=True, index=True)
    likes      = db.Column(db.Integer, default=0, nullable=False)
    views      = db.Column(db.Integer, default=0, nullable=False)
    reports    = db.Column(db.Integer, default=0, nullable=False)
    author_fp  = db.Column(db.String(128), index=True, nullable=True)

# índice explícito (por si SQLite ignora el de la columna)
Index("ix_notes_author_fp", Note.author_fp)
PY

# run.py limpio
cat > run.py <<PY
from __future__ import annotations

from flask import Flask
from backend import db

app = Flask(__name__)
app.config["SQLALCHEMY_DATABASE_URI"] = "${DBURI}"
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

db.init_app(app)

from backend.routes import api as api_blueprint  # noqa: E402
app.register_blueprint(api_blueprint)

with app.app_context():
    db.create_all()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
PY

# Validar sintaxis
python -m py_compile backend/models.py run.py

# Reinicio rápido
pkill -f "python .*run\.py" 2>/dev/null || true
pkill -f "waitress" 2>/dev/null || true
pkill -f "flask" 2>/dev/null || true
sleep 1
nohup python run.py >"$LOG" 2>&1 & disown || true
sleep 2

# Smokes
echo "health=$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/api/health)"
echo "notes_get=$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/api/notes)"
echo "notes_post=$(curl -sS -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' \
  -d '{\"text\":\"nota ok newlines\",\"hours\":24}' http://127.0.0.1:8000/api/notes)"

# Commit
git add backend/models.py run.py
git commit -m "chore(format): reparar saltos de línea en models/run; formato estable"
git push origin main || true

echo "Log: $LOG  (tail -n 120 \"$LOG\")"
