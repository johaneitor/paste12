from __future__ import annotations
import os, hashlib
from datetime import datetime, timedelta
from flask import Flask, Blueprint, jsonify, request

USING_FACTORY = False
app = None
db = None
Note = None

# 1) Intenta usar tu factory/ORM reales
try:
    from backend import create_app, db as _db
    from backend.models import Note as _Note
    app = create_app()
    db = _db
    Note = _Note
    USING_FACTORY = True
except Exception:
    pass

# 2) Fallback mínimo si no hay factory/ORM
if app is None:
    from flask_sqlalchemy import SQLAlchemy
    app = Flask(__name__)
    app.config["SQLALCHEMY_DATABASE_URI"] = os.environ.get("DATABASE_URL", "sqlite:///app.db")
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
    db = SQLAlchemy(app)

    class Note(db.Model):  # mínimo compatible
        __tablename__ = "note"
        id = db.Column(db.Integer, primary_key=True)
        text = db.Column(db.Text, nullable=False)
        timestamp = db.Column(db.DateTime, nullable=False, index=True)
        expires_at = db.Column(db.DateTime, nullable=False, index=True)
        likes = db.Column(db.Integer, default=0, nullable=False)
        views = db.Column(db.Integer, default=0, nullable=False)
        reports = db.Column(db.Integer, default=0, nullable=False)
        author_fp = db.Column(db.String(64), nullable=False, index=True, default="noctx")

# ---- Helpers ----
def _now(): return datetime.utcnow()

def _fp() -> str:
    ip = request.headers.get("X-Forwarded-For","") or request.headers.get("CF-Connecting-IP","") or (request.remote_addr or "")
    ua = request.headers.get("User-Agent","")
    salt = os.environ.get("FP_SALT","")
    try:
        return hashlib.sha256(f"{ip}|{ua}|{salt}".encode()).hexdigest()[:32]
    except Exception:
        return "noctx"

def _note_json(n: Note, now: datetime | None = None) -> dict:
    now = now or _now()
    toiso = lambda d: (d.isoformat() if d else None)
    return {
        "id": n.id, "text": n.text,
        "timestamp": toiso(getattr(n, "timestamp", None)),
        "expires_at": toiso(getattr(n, "expires_at", None)),
        "likes": getattr(n, "likes", 0),
        "views": getattr(n, "views", 0),
        "reports": getattr(n, "reports", 0),
        "author_fp": getattr(n, "author_fp", None),
        "now": now.isoformat(),
    }

# ---- Blueprint forzado (/api) ----
bp_forced = Blueprint("api_forced_notes", __name__)

@bp_forced.get("/notes", endpoint="forced_list_notes")
def forced_list_notes():
    try:
        page = 1
        try:
            page = max(1, int(request.args.get("page", 1)))
        except Exception:
            pass
        q = Note.query.order_by(Note.timestamp.desc())
        items = q.limit(20).offset((page-1)*20).all()
        return jsonify([_note_json(n) for n in items]), 200
    except Exception as e:
        return jsonify(ok=False, error="list_failed", detail=str(e)), 500

@bp_forced.post("/notes", endpoint="forced_create_note")
def forced_create_note():
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

@bp_forced.get("/debug-urlmap", endpoint="forced_debug_urlmap")
def forced_debug_urlmap():
    rules = []
    for r in app.url_map.iter_rules():
        methods = sorted([m for m in r.methods if m not in ("HEAD","OPTIONS")])
        rules.append({"rule": str(r), "endpoint": r.endpoint, "methods": methods})
    return jsonify({"rules": rules, "using_factory": USING_FACTORY})

# /api/health (solo si no existe)
def _has_health():
    for r in app.url_map.iter_rules():
        if str(r) == "/api/health":
            return True
    return False

if not _has_health():
    @bp_forced.get("/health", endpoint="forced_health")
    def forced_health():
        return jsonify(ok=True, note="wsgi"), 200

# Registrar siempre el blueprint forzado bajo /api
try:
    app.register_blueprint(bp_forced, url_prefix="/api")
except Exception:
    # Si ya estaba registrado, seguimos.
    pass

# Crear tablas si faltan (idempotente)
try:
    with app.app_context():
        db.create_all()
except Exception:
    pass
