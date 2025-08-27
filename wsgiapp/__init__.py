# wsgiapp bridge: siempre exporta `app`, agrega /api/debug-urlmap y fallback /api/notes con SQLAlchemy(app)
from __future__ import annotations
import os, hashlib
from datetime import datetime, timedelta
from flask import Flask, Blueprint, jsonify, request

# 1) Obtener/crear la app base
app = None
try:
    from render_entry import app as app  # si existe, úsala
except Exception:
    try:
        from wsgi import app as app      # segundo intento
    except Exception:
        app = Flask(__name__)            # fallback mínimo
        @app.get("/api/health")
        def _health():
            return jsonify(ok=True, note="wsgiapp-package-fallback"), 200

# 2) Blueprint puente (debug + fallback notes)
bp = Blueprint("bridge_probe", __name__)

@bp.get("/bridge-ping")
def bridge_ping():
    return jsonify(ok=True, where="wsgiapp.__init__", note=app.import_name), 200

@bp.get("/debug-urlmap")
def debug_urlmap():
    rules = []
    for r in app.url_map.iter_rules():
        methods = sorted([m for m in r.methods if m not in ("HEAD","OPTIONS")])
        rules.append({"rule": str(r), "endpoint": r.endpoint, "methods": methods})
    return jsonify(ok=True, rules=rules), 200

# Helpers
def _now(): return datetime.utcnow()
def _fp(req:request)->str:
    try:
        ip = req.headers.get("X-Forwarded-For","") or req.headers.get("CF-Connecting-IP","") or (req.remote_addr or "")
        ua = req.headers.get("User-Agent","")
        salt = os.environ.get("FP_SALT","")
        return hashlib.sha256(f"{ip}|{ua}|{salt}".encode()).hexdigest()[:32]
    except Exception:
        return "noctx"

def _has(path:str, method:str)->bool:
    try:
        for r in app.url_map.iter_rules():
            if str(r)==path and method.upper() in r.methods:
                return True
    except Exception:
        pass
    return False

# 3) Fallback /api/notes → usar SIEMPRE una instancia local de SQLAlchemy(app)
#    así evitamos "app not registered with this SQLAlchemy instance".
from flask_sqlalchemy import SQLAlchemy
if not (_has("/api/notes","GET") and _has("/api/notes","POST")):
    db = SQLAlchemy(app)  # ligado a ESTA app
    class Note(db.Model):
        __tablename__ = "note"
        id = db.Column(db.Integer, primary_key=True)
        text = db.Column(db.Text, nullable=False)
        timestamp = db.Column(db.DateTime, nullable=False, index=True)
        expires_at = db.Column(db.DateTime, nullable=False, index=True)
        likes = db.Column(db.Integer, default=0, nullable=False)
        views = db.Column(db.Integer, default=0, nullable=False)
        reports = db.Column(db.Integer, default=0, nullable=False)
        author_fp = db.Column(db.String(64), nullable=False, default="noctx", index=True)

    with app.app_context():
        db.create_all()

    def _note_json(n, now=None):
        now = now or _now()
        toiso = lambda d: (d.isoformat() if d else None)
        return {
            "id": n.id, "text": n.text,
            "timestamp": toiso(getattr(n,"timestamp",None)),
            "expires_at": toiso(getattr(n,"expires_at",None)),
            "likes": getattr(n,"likes",0),
            "views": getattr(n,"views",0),
            "reports": getattr(n,"reports",0),
            "author_fp": getattr(n,"author_fp",None),
            "now": now.isoformat(),
        }

    @bp.get("/notes", endpoint="bridge_list_notes")
    def bridge_list_notes():
        try:
            page = 1
            try: page = max(1, int(request.args.get("page", 1)))
            except Exception: pass
            q = Note.query.order_by(Note.timestamp.desc())
            items = q.limit(20).offset((page-1)*20).all()
            return jsonify([_note_json(n) for n in items]), 200
        except Exception as e:
            return jsonify(ok=False, error="list_failed", detail=str(e)), 500

    @bp.post("/notes", endpoint="bridge_create_note")
    def bridge_create_note():
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
                author_fp=_fp(request),
            )
            db.session.add(n)
            db.session.commit()
            return jsonify(_note_json(n, now)), 201
        except SQLAlchemyError as e:
            db.session.rollback()
            return jsonify(ok=False, error="create_failed", detail=str(e)), 500
        except Exception as e:
            return jsonify(ok=False, error="create_failed", detail=str(e)), 500

# 4) Registrar blueprint bajo /api (idempotente)
try:
    app.register_blueprint(bp, url_prefix="/api")
except Exception:
    pass
