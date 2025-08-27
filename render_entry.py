from __future__ import annotations
import os, hashlib
from importlib import import_module
from datetime import datetime, timedelta
from flask import Blueprint, jsonify, request

# 1) Traemos la app real desde wsgi.py (tu app de verdad vive ahí)
_w = import_module("wsgi")
app = getattr(_w, "app")
db  = getattr(_w, "db",  None)
Note= getattr(_w, "Note", None)

# 2) Helpers
def _now(): return datetime.utcnow()
def _has(rule: str, method: str|None=None) -> bool:
    for r in app.url_map.iter_rules():
        if str(r) == rule:
            return True if method is None else (method in r.methods)
    return False

def _fp() -> str:
    try:
        ip = request.headers.get("X-Forwarded-For","") or request.headers.get("CF-Connecting-IP","") or (request.remote_addr or "")
        ua = request.headers.get("User-Agent","")
        salt = os.environ.get("FP_SALT","")
        return hashlib.sha256(f"{ip}|{ua}|{salt}".encode()).hexdigest()[:32]
    except Exception:
        return "noctx"

def _note_json(n, now=None):
    now = now or _now()
    iso = lambda d: (d.isoformat() if d else None)
    return {
        "id": getattr(n, "id", None),
        "text": getattr(n, "text", None),
        "timestamp": iso(getattr(n, "timestamp", None)),
        "expires_at": iso(getattr(n, "expires_at", None)),
        "likes": getattr(n, "likes", 0),
        "views": getattr(n, "views", 0),
        "reports": getattr(n, "reports", 0),
        "author_fp": getattr(n, "author_fp", None),
        "now": now.isoformat(),
    }

# 3) Debug siempre disponible
dbg = Blueprint("render_entry_dbg", __name__)
@dbg.get("/debug-urlmap")
def debug_urlmap():
    rules=[]
    for r in app.url_map.iter_rules():
        methods = sorted([m for m in r.methods if m not in ("HEAD","OPTIONS")])
        rules.append({"rule": str(r), "endpoint": r.endpoint, "methods": methods})
    return jsonify({"rules": rules, "source": "render_entry"})
@dbg.get("/bridge-ping")
def bridge_ping():
    return jsonify({
        "has_get": _has("/api/notes","GET"),
        "has_post": _has("/api/notes","POST"),
        "has_debug": _has("/api/debug-urlmap","GET"),
    })
try:
    app.register_blueprint(dbg, url_prefix="/api")
except Exception:
    pass

# 4) Si faltan /api/notes GET/POST, inyectamos fallback aquí mismo
need_get  = not _has("/api/notes","GET")
need_post = not _has("/api/notes","POST")

if need_get or need_post:
    # ORM mínimo si la app real no expuso db/Note
    if db is None or Note is None:
        from flask_sqlalchemy import SQLAlchemy
        from flask import current_app
        db = SQLAlchemy(app)
        class Note(db.Model):  # noqa
            __tablename__ = "note"
            id = db.Column(db.Integer, primary_key=True)
            text = db.Column(db.Text, nullable=False)
            timestamp = db.Column(db.DateTime, nullable=False, index=True)
            expires_at = db.Column(db.DateTime, nullable=False, index=True)
            likes = db.Column(db.Integer, default=0, nullable=False)
            views = db.Column(db.Integer, default=0, nullable=False)
            reports = db.Column(db.Integer, default=0, nullable=False)
            author_fp = db.Column(db.String(64), nullable=False, index=True, default="noctx")
        with app.app_context():
            db.create_all()

    bp = Blueprint("render_entry_notes", __name__)
    if need_get:
        @bp.get("/notes")
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

    if need_post:
        @bp.post("/notes")
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

    try:
        app.register_blueprint(bp, url_prefix="/api")
    except Exception:
        pass

# 5) Exponer para gunicorn:  gunicorn render_entry:app
__all__ = ["app"]
