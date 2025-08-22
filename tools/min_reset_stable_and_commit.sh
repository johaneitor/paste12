#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(pwd)"
DATA_DIR="$ROOT/data"
ABS_DB="$(python - <<'PY'
import os; print(os.path.abspath('data/app.db'))
PY
)"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
TMPDIR="${TMPDIR:-$PREFIX/tmp}"
LOG="$TMPDIR/paste12_server.log"

mkdir -p "$DATA_DIR" "$TMPDIR"

backup(){ [ -f "$1" ] && cp -f "$1" "$1.bak.$(date +%s)" || true; }
echo "➤ Backups"
backup backend/__init__.py
backup backend/models.py
backup backend/routes.py
backup run.py

echo "➤ backend/__init__.py"
cat > backend/__init__.py <<'PY'
from flask_sqlalchemy import SQLAlchemy
db = SQLAlchemy()
PY

echo "➤ backend/models.py"
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

Index("ix_notes_author_fp", Note.author_fp)
PY

echo "➤ backend/routes.py"
cat > backend/routes.py <<'PY'
from __future__ import annotations

from flask import Blueprint, request, jsonify
from hashlib import sha256
from datetime import datetime, timedelta

from backend import db
from backend.models import Note

api = Blueprint("api", __name__, url_prefix="/api")

def _fingerprint_from_request(req):
    ip = (req.headers.get("X-Forwarded-For") or getattr(req, "remote_addr", "") or "").split(",")[0].strip()
    ua = req.headers.get("User-Agent", "")
    return sha256(f"{ip}|{ua}".encode("utf-8")).hexdigest()

def _note_to_dict(n: Note):
    return {
        "id": n.id,
        "text": getattr(n, "text", None),
        "timestamp": n.timestamp.isoformat() if getattr(n, "timestamp", None) else None,
        "expires_at": n.expires_at.isoformat() if getattr(n, "expires_at", None) else None,
        "likes": getattr(n, "likes", 0) or 0,
        "views": getattr(n, "views", 0) or 0,
        "reports": getattr(n, "reports", 0) or 0,
    }

@api.route("/health", methods=["GET"])
def health():
    return jsonify({"ok": True})

@api.route("/notes", methods=["GET"])
def list_notes():
    try:
        page = int((request.args.get("page") or "1").strip() or "1")
    except Exception:
        page = 1
    if page < 1:
        page = 1
    q = db.session.query(Note).order_by(Note.id.desc())
    items = q.limit(20).offset((page - 1) * 20).all()
    return jsonify([_note_to_dict(n) for n in items])

@api.route("/notes", methods=["POST"])
def create_note():
    data = request.get_json(silent=True) or {}
    text = (data.get("text") or "").strip()
    try:
        hours = int(data.get("hours") or 24)
    except Exception:
        hours = 24
    if not text:
        return jsonify({"error": "text_required"}), 400
    hours = max(1, min(hours, 720))
    now = datetime.utcnow()
    try:
        n = Note(
            text=text,
            timestamp=now,
            expires_at=now + timedelta(hours=hours),
            author_fp=_fingerprint_from_request(request),
        )
        db.session.add(n)
        db.session.commit()
        return jsonify({"id": n.id, "ok": True}), 201
    except Exception as e:
        db.session.rollback()
        return jsonify({"error": "create_failed", "detail": str(e)}), 500

@api.route("/notes/<int:note_id>/view", methods=["POST"])
def view_note(note_id: int):
    n = db.session.get(Note, note_id)
    if not n:
        return jsonify({"error": "not_found"}), 404
    n.views = (n.views or 0) + 1
    db.session.commit()
    return jsonify({"ok": True, "views": n.views})

@api.route("/notes/<int:note_id>/like", methods=["POST"])
def like_note(note_id: int):
    n = db.session.get(Note, note_id)
    if not n:
        return jsonify({"error": "not_found"}), 404
    n.likes = (n.likes or 0) + 1
    db.session.commit()
    return jsonify({"ok": True, "likes": n.likes})

@api.route("/notes/<int:note_id>/report", methods=["POST"])
def report_note(note_id: int):
    n = db.session.get(Note, note_id)
    if not n:
        return jsonify({"error": "not_found"}), 404
    n.reports = (n.reports or 0) + 1
    db.session.commit()
    return jsonify({"ok": True, "reports": n.reports})
PY

echo "➤ run.py"
cat > run.py <<PY
from __future__ import annotations

from flask import Flask
from backend import db

app = Flask(__name__)
app.config["SQLALCHEMY_DATABASE_URI"] = "sqlite:///${ABS_DB}"
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

db.init_app(app)

from backend.routes import api as api_blueprint  # noqa: E402
app.register_blueprint(api_blueprint)

with app.app_context():
    db.create_all()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
PY

echo "➤ Kill & clean"
pkill -f "python .*run\.py" 2>/dev/null || true
pkill -f "waitress" 2>/dev/null || true
pkill -f "flask" 2>/dev/null || true
find backend -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true
find backend -name '*.pyc' -delete 2>/dev/null || true

echo "➤ Start (log: $LOG)"
nohup python run.py >"$LOG" 2>&1 & disown || true
sleep 2

echo "➤ URL map (parcial)"
python - <<'PY'
from run import app
for r in sorted(app.url_map.iter_rules(), key=lambda r: r.rule):
    if "/api" in r.rule:
        print(f" {r.rule:28s} {sorted(list(r.methods))} {r.endpoint}")
PY

echo "➤ Smokes"
for u in /api/health /api/notes; do
  printf "%-14s -> " "$u"
  curl -sS -m 6 -o /dev/null -w "%{http_code}\n" "http://127.0.0.1:8000$u"
done
printf "POST /api/notes -> "
curl -sS -m 8 -H "Content-Type: application/json" -d '{"text":"nota estable","hours":24}' -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8000/api/notes

echo "➤ Mapper cols de Note"
python - <<'PY'
from run import app
from backend.models import Note
with app.app_context():
    print([c.name for c in Note.__table__.columns])
PY

echo "➤ Commit & push"
git add -A
git commit -m "refactor(minimal): reset estable Flask+SQLAlchemy; rutas /api y Note(author_fp) funcionando"
git push origin main || true

echo "OK. Si algo falla, tail -n 200 \"$LOG\""
