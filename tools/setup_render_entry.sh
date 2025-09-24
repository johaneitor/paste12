#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"

echo "[+] Escribiendo render_entry.py (entrypoint determinístico)"
cat > render_entry.py <<'PY'
from __future__ import annotations
import os, hashlib
from datetime import datetime, timedelta
from flask import Flask, Blueprint, jsonify, request

app = None
db = None
Note = None

# 1) Intenta usar tu factory/ORM reales si existen
try:
    from backend import create_app, db as _db
    from backend.models import Note as _Note
    app = create_app()
    db = _db
    Note = _Note
except Exception:
    pass

# 2) Fallback mínimo si no hay factory/ORM
if app is None:
    from flask_sqlalchemy import SQLAlchemy
    app = Flask(__name__)
    app.config["SQLALCHEMY_DATABASE_URI"] = os.environ.get("DATABASE_URL", "sqlite:///app.db")
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
    db = SQLAlchemy(app)
    class Note(db.Model):
        __tablename__ = "note"
        id = db.Column(db.Integer, primary_key=True)
        text = db.Column(db.Text, nullable=False)
        timestamp = db.Column(db.DateTime, nullable=False, index=True)
        expires_at = db.Column(db.DateTime, nullable=False, index=True)
        likes = db.Column(db.Integer, default=0, nullable=False)
        views = db.Column(db.Integer, default=0, nullable=False)
        reports = db.Column(db.Integer, default=0, nullable=False)
        author_fp = db.Column(db.String(64), nullable=False, index=True, default="noctx")

def _now(): return datetime.utcnow()
def _fp() -> str:
    try:
        ip = request.headers.get("X-Forwarded-For","") or request.headers.get("CF-Connecting-IP","") or (request.remote_addr or "")
        ua = request.headers.get("User-Agent","")
        salt = os.environ.get("FP_SALT","")
        return hashlib.sha256(f"{ip}|{ua}|{salt}".encode()).hexdigest()[:32]
    except Exception:
        return "noctx"

def _has(path:str, method:str) -> bool:
    for r in app.url_map.iter_rules():
        if str(r) == path and method.upper() in r.methods:
            return True
    return False

def _note_json(n: Note, now: datetime | None = None) -> dict:
    now = now or _now()
    toiso = lambda d: (d.isoformat() if d else None)
    return {
        "id": n.id,
        "text": n.text,
        "timestamp": toiso(getattr(n, "timestamp", None)),
        "expires_at": toiso(getattr(n, "expires_at", None)),
        "likes": getattr(n, "likes", 0),
        "views": getattr(n, "views", 0),
        "reports": getattr(n, "reports", 0),
        "author_fp": getattr(n, "author_fp", None),
        "now": now.isoformat(),
    }

# 3) Blueprint API (debug + fallback /notes si faltaran)
api = Blueprint("api", __name__)

@api.get("/health")
def health():
    # Esto nos permite ver que efectivamente se está usando este entrypoint
    return jsonify(ok=True, note="render_entry"), 200

@api.get("/debug-urlmap")
def debug_urlmap():
    rules = []
    for r in app.url_map.iter_rules():
        methods = sorted([m for m in r.methods if m not in ("HEAD","OPTIONS")])
        rules.append({"rule": str(r), "endpoint": r.endpoint, "methods": methods})
    return jsonify(ok=True, rules=rules), 200

# Solo agrega /api/notes si no existen ya (idempotente)
if Note and not (_has("/api/notes","GET") and _has("/api/notes","POST")):
    @api.get("/notes")
    def list_notes():
        try:
            page = 1
            try: page = max(1, int(request.args.get("page", 1)))
            except Exception: pass
            q = Note.query.order_by(Note.timestamp.desc())
            items = q.limit(20).offset((page-1)*20).all()
            return jsonify([_note_json(n) for n in items]), 200
        except Exception as e:
            return jsonify(ok=False, error="list_failed", detail=str(e)), 500

    @api.post("/notes")
    def create_note():
        from sqlalchemy.exc import SQLAlchemyError
        try:
            data = request.get_json(silent=True) or {}
            text = (data.get("text") or "").strip()
            if not text:
                return jsonify(error="text required"), 400
            try:
                hours = int(data.get("hours", 24))
            except Exception:
                hours = 24
            hours = min(168, max(1, hours))
            now = _now()
            n = Note(
                text=text,
                timestamp=now,
                expires_at=now + timedelta(hours=hours),
                author_fp=_fp(),
            )
            db.session.add(n)
            db.session.commit()
            return jsonify(_note_json(n, now)), 201
        except SQLAlchemyError as e:
            db.session.rollback()
            return jsonify(ok=False, error="create_failed", detail=str(e)), 500
        except Exception as e:
            return jsonify(ok=False, error="create_failed", detail=str(e)), 500

# 4) Registrar blueprint bajo /api
try:
    app.register_blueprint(api, url_prefix="/api")
except Exception:
    pass

# 5) Crear tablas si faltan (idempotente)
try:
    with app.app_context():
        if db is not None:
            db.create_all()
except Exception:
    pass
PY

echo "[+] git add/commit/push"
git add -A
git commit -m "chore: add render_entry.py (deterministic entrypoint with /api/notes fallback + debug-urlmap + create_all)" || true
git push -u --force-with-lease origin "$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"

echo
echo "==============================================="
echo "[!] En Render, cambia el Start Command a:"
echo "    gunicorn -w \${WEB_CONCURRENCY:-2} -k gthread --threads \${THREADS:-4} -b 0.0.0.0:\$PORT render_entry:app"
echo "    (y redeploy; si persiste, Clear build cache)"
echo "==============================================="
