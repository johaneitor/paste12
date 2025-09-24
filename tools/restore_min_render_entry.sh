#!/usr/bin/env bash
set -euo pipefail

F="render_entry.py"
BKP="$F.bak.$(date +%Y%m%d-%H%M%S)"
[ -f "$F" ] && cp -a "$F" "$BKP" && echo "[i] Backup en $BKP"

cat > "$F" <<'PY'
from __future__ import annotations
import os, hashlib
from datetime import datetime, timedelta
from flask import Flask, Blueprint, jsonify, request

# --- Contexto global (se rellenará con factory real o fallback) ---
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
        id         = db.Column(db.Integer, primary_key=True)
        text       = db.Column(db.Text, nullable=False)
        timestamp  = db.Column(db.DateTime, nullable=False, index=True, default=datetime.utcnow)
        expires_at = db.Column(db.DateTime, nullable=False, index=True, default=datetime.utcnow)
        likes      = db.Column(db.Integer, default=0, nullable=False)
        views      = db.Column(db.Integer, default=0, nullable=False)
        reports    = db.Column(db.Integer, default=0, nullable=False)
        author_fp  = db.Column(db.String(64), nullable=False, index=True, default="noctx")
    with app.app_context():
        db.create_all()

# --- Helpers ---
def _now() -> datetime:
    return datetime.utcnow()

def _fp() -> str:
    try:
        ip = request.headers.get("X-Forwarded-For","") or request.headers.get("CF-Connecting-IP","") or (request.remote_addr or "")
        ua = request.headers.get("User-Agent","")
        salt = os.environ.get("FP_SALT","")
        return hashlib.sha256(f"{ip}|{ua}|{salt}".encode()).hexdigest()[:32]
    except Exception:
        return "noctx"

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

# --- API Blueprint ---
api = Blueprint("api", __name__)

@api.get("/health")
def health():
    return jsonify(ok=True, note="render_entry"), 200

@api.get("/debug-urlmap")
def debug_urlmap():
    rules = []
    for r in app.url_map.iter_rules():
        methods = sorted([m for m in r.methods if m not in ("HEAD","OPTIONS")])
        rules.append({"rule": str(r), "endpoint": r.endpoint, "methods": methods})
    return jsonify(ok=True, rules=rules), 200

@api.get("/notes")
def list_notes():
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

# Registrar blueprint principal
app.register_blueprint(api, url_prefix="/api")

# --- Interactions (si está el módulo, se registra) ---
try:
    from backend.modules.interactions import (
        bp as ix_bp,
        alias_bp as ix_alias_bp,
        ensure_schema as ix_ensure_schema,
    )
    with app.app_context():
        ix_ensure_schema()
    try:
        app.register_blueprint(ix_bp, url_prefix="/api")
    except Exception:
        pass
    try:
        app.register_blueprint(ix_alias_bp, url_prefix="/api")
    except Exception:
        pass
except Exception:
    pass

# --- Diag & repair mínimos para interacciones ---
from flask import Blueprint as _BP_, jsonify as _jsonify_
ixdiag = _BP_("ixdiag_render_entry", __name__)

@ixdiag.get("/notes/diag")
def notes_diag():
    try:
        from sqlalchemy import inspect as _inspect, func as _func
        eng = db.get_engine()
        inspector = _inspect(eng)
        tables = inspector.get_table_names()
        out = {"tables": tables, "has_interaction_event": ("interaction_event" in tables)}
        if out["has_interaction_event"]:
            from backend.modules.interactions import InteractionEvent
            likes_cnt = db.session.query(_func.count(InteractionEvent.id)).filter_by(type="like").scalar() or 0
            views_cnt = db.session.query(_func.count(InteractionEvent.id)).filter_by(type="view").scalar() or 0
            out["total_likes"] = int(likes_cnt)
            out["total_views"] = int(views_cnt)
        return _jsonify_(ok=True, **out), 200
    except Exception as e:
        return _jsonify_(ok=False, error="diag_failed", detail=str(e)), 500

@ixdiag.post("/notes/repair-interactions")
def repair_interactions():
    try:
        from backend.modules.interactions import ensure_schema as _ens
        with app.app_context():
            _ens()
        return _jsonify_(ok=True, repaired=True), 200
    except Exception as e:
        return _jsonify_(ok=False, error="repair_failed", detail=str(e)), 500

try:
    app.register_blueprint(ixdiag, url_prefix="/api")
except Exception:
    pass

# WSGI app export
#   Start Command recomendado en Render:
#   gunicorn render_entry:app -w ${WEB_CONCURRENCY:-2} -k gthread --threads ${THREADS:-4} --bind 0.0.0.0:$PORT
PY

echo "[i] Archivo escrito: $F"

echo "[i] Verificando sintaxis…"
python -m py_compile "$F" && echo "[ok] py_compile OK"

echo "[i] Primeras 60 líneas:"
nl -ba "$F" | sed -n '1,60p'
