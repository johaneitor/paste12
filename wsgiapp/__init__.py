# wsgiapp bridge V2: /api/debug-urlmap + /api/notes con DB lazy y shim en memoria
from __future__ import annotations
import os, hashlib
from datetime import datetime, timedelta
from flask import Flask, Blueprint, jsonify, request

# 1) App base
app = None
try:
    from render_entry import app as app
except Exception:
    try:
        from wsgi import app as app
    except Exception:
        app = Flask(__name__)
        @app.get("/api/health")
        def _health():
            return jsonify(ok=True, note="wsgiapp-package-fallback"), 200

# 2) Blueprint puente
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

# 3) Setup de modelo/DB (sin bloquear el registro de rutas)
_db = None
_Note = None
_mem = {"seq": 0, "items": []}  # shim en memoria si DB falla

def _note_json(n, now=None):
    now = now or _now()
    toiso = lambda d: (d.isoformat() if d else None)
    # Soporta objeto DB o dict del shim
    if isinstance(n, dict):
        return {
            "id": n["id"], "text": n["text"],
            "timestamp": toiso(n.get("timestamp")),
            "expires_at": toiso(n.get("expires_at")),
            "likes": n.get("likes", 0),
            "views": n.get("views", 0),
            "reports": n.get("reports", 0),
            "author_fp": n.get("author_fp"),
            "now": now.isoformat(),
        }
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

def _ensure_db():
    """Inicializa SQLAlchemy ligado a ESTA app y crea tablas. Devuelve (db, Note) o (None, None) si falla."""
    global _db, _Note
    if _db is not None and _Note is not None:
        return _db, _Note
    try:
        from flask_sqlalchemy import SQLAlchemy
    except Exception:
        return None, None
    try:
        _db = SQLAlchemy(app)
        class Note(_db.Model):
            __tablename__ = "note"
            id = _db.Column(_db.Integer, primary_key=True)
            text = _db.Column(_db.Text, nullable=False)
            timestamp = _db.Column(_db.DateTime, nullable=False, index=True)
            expires_at = _db.Column(_db.DateTime, nullable=False, index=True)
            likes = _db.Column(_db.Integer, default=0, nullable=False)
            views = _db.Column(_db.Integer, default=0, nullable=False)
            reports = _db.Column(_db.Integer, default=0, nullable=False)
            author_fp = _db.Column(_db.String(64), nullable=False, default="noctx", index=True)
        _Note = Note
        try:
            with app.app_context():
                _db.create_all()
        except Exception:
            # Aunque falle create_all, mantenemos modelo para operaciones que puedan funcionar luego
            pass
        return _db, _Note
    except Exception:
        _db, _Note = None, None
        return None, None

# 4) Registrar SIEMPRE las rutas /api/notes si faltan (la lógica interna es tolerante a fallos de DB)
if not (_has("/api/notes","GET") and _has("/api/notes","POST")):

    @bp.get("/notes", endpoint="bridge_list_notes")
    def bridge_list_notes():
        db, Note = _ensure_db()
        # DB OK → leer desde DB
        if db and Note:
            try:
                page = 1
                try: page = max(1, int(request.args.get("page", 1)))
                except Exception: pass
                q = Note.query.order_by(Note.timestamp.desc())
                items = q.limit(20).offset((page-1)*20).all()
                return jsonify([_note_json(n) for n in items]), 200
            except Exception as e:
                # cae a shim en memoria
                pass
        # Shim en memoria
        try:
            page = 1
            try: page = max(1, int(request.args.get("page", 1)))
            except Exception: pass
            start = (page-1)*20
            end = start+20
            items = sorted(_mem["items"], key=lambda x: x["timestamp"], reverse=True)[start:end]
            return jsonify([_note_json(n) for n in items]), 200
        except Exception as e:
            return jsonify(ok=False, error="list_failed", detail=str(e)), 500

    @bp.post("/notes", endpoint="bridge_create_note")
    def bridge_create_note():
        db, Note = _ensure_db()
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
        # Intento DB real
        if db and Note:
            try:
                n = Note(
                    text=text,
                    timestamp=now,
                    expires_at=now + timedelta(hours=hours),
                    author_fp=_fp(request),
                )
                db.session.add(n)
                db.session.commit()
                return jsonify(_note_json(n, now)), 201
            except Exception:
                # rollback y caer a shim
                try: db.session.rollback()
                except Exception: pass
        # Shim en memoria
        try:
            _mem["seq"] += 1
            n = {
                "id": _mem["seq"],
                "text": text,
                "timestamp": now,
                "expires_at": now + timedelta(hours=hours),
                "likes": 0, "views": 0, "reports": 0,
                "author_fp": _fp(request),
            }
            _mem["items"].append(n)
            return jsonify(_note_json(n, now)), 201
        except Exception as e:
            return jsonify(ok=False, error="create_failed", detail=str(e)), 500

# 5) Registrar blueprint bajo /api (idempotente)
try:
    app.register_blueprint(bp, url_prefix="/api")
except Exception:
    pass
