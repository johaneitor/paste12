#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(pwd)"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
TMPDIR="${TMPDIR:-$PREFIX/tmp}"
LOG="$TMPDIR/paste12_server.log"
DBURI="sqlite:////data/data/com.termux/files/home/paste12/data/app.db"

mkdir -p "$TMPDIR" data
cp -f backend/models.py "backend/models.py.bak.$(date +%s)" 2>/dev/null || true
cp -f run.py "run.py.bak.$(date +%s)" 2>/dev/null || true

# --- models.py limpio (sin duplicados) ---
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

# --- run.py estable ---
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

# --- restart + smokes ---
pkill -f "python .*run\.py" 2>/dev/null || true
pkill -f "waitress" 2>/dev/null || true
pkill -f "flask" 2>/dev/null || true
find backend -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true
find backend -name '*.pyc' -delete 2>/dev/null || true

nohup python run.py >"$LOG" 2>&1 & disown || true
sleep 2

echo "health=$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/api/health)"
echo "notes_get=$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/api/notes)"
echo "notes_post=$(curl -sS -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' \
  -d '{\"text\":\"nota tras cleanup\",\"hours\":24}' http://127.0.0.1:8000/api/notes)"

python - <<'PY'
from run import app
from backend.models import Note
with app.app_context():
    print("cols:", [c.name for c in Note.__table__.columns])
PY

# --- commit + push ---
git add backend/models.py run.py
git commit -m "fix(models/run): dedupe columnas Note; run.py estable con blueprint y create_all"
git push origin main || true

echo "Log: $LOG (tail -n 120 \"$LOG\")"
