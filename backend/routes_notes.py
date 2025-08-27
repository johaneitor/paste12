from __future__ import annotations
import hashlib, os
from datetime import datetime, timedelta
from flask import Blueprint, jsonify, request

def _now(): 
    return datetime.utcnow()

def _fp(req) -> str:
    ip = req.headers.get("X-Forwarded-For","") or req.headers.get("CF-Connecting-IP","") or (req.remote_addr or "")
    ua = req.headers.get("User-Agent","")
    salt = os.environ.get("FP_SALT","")
    return hashlib.sha256(f"{ip}|{ua}|{salt}".encode()).hexdigest()[:32]

def _has_rule(app, rule: str, method: str) -> bool:
    try:
        for r in app.url_map.iter_rules():
            if str(r) == rule and method.upper() in r.methods:
                return True
    except Exception:
        pass
    return False

def register_api(app):
    """
    Registra /api/notes GET y POST si no existen aún. Idempotente.
    Requiere backend.models.Note y backend.db ya inicializados por create_app().
    """
    if _has_rule(app, "/api/notes", "GET") and _has_rule(app, "/api/notes", "POST"):
        return "present"

    from backend import db
    from backend.models import Note  # debe existir el modelo con author_fp

    api_bp = Blueprint("api_notes_capsule", __name__)

    @api_bp.get("/notes")
    def list_notes():
        page = max(1, int(request.args.get("page", 1) or 1))
        q = Note.query.order_by(Note.timestamp.desc())
        items = q.limit(20).offset((page-1)*20).all()
        now = _now()
        out = []
        for n in items:
            out.append({
                "id": n.id,
                "text": n.text,
                "timestamp": n.timestamp.isoformat(),
                "expires_at": n.expires_at.isoformat() if n.expires_at else None,
                "likes": n.likes,
                "views": n.views,
                "reports": n.reports,
                "author_fp": getattr(n, "author_fp", None),
                "now": now.isoformat(),
            })
        return jsonify(out), 200

    @api_bp.post("/notes")
    def create_note():
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
        return jsonify({
            "id": n.id,
            "text": n.text,
            "timestamp": n.timestamp.isoformat(),
            "expires_at": n.expires_at.isoformat() if n.expires_at else None,
            "likes": n.likes,
            "views": n.views,
            "reports": n.reports,
            "author_fp": getattr(n, "author_fp", None),
            "now": now.isoformat(),
        }), 201

    app.register_blueprint(api_bp, url_prefix="/api")
    return "registered"
