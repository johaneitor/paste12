from __future__ import annotations
from flask import Blueprint, jsonify, request
from datetime import datetime, timedelta
import os, hashlib

api = Blueprint("api", __name__)

try:
    from backend import db
    from backend.models import Note
except Exception as e:
    db = None
    Note = None
    print("~ backend.api: no pude importar db/Note:", e)

def _now() -> datetime: return datetime.utcnow()

def _fp() -> str:
    try:
        ip = request.headers.get("X-Forwarded-For","") or request.headers.get("CF-Connecting-IP","") or (request.remote_addr or "")
        ua = request.headers.get("User-Agent","")
    except Exception: return "noctx"
    salt = os.environ.get("FP_SALT","")
    return hashlib.sha256(f"{ip}|{ua}|{salt}".encode()).hexdigest()[:32]

@api.get("/notes")
def list_notes():
    if Note is None or db is None:
        return jsonify(error="backend_api_fallback_missing_models"), 500
    page = max(1, int(request.args.get("page", 1) or 1))
    q = Note.query.order_by(Note.timestamp.desc())
    items = q.limit(20).offset((page-1)*20).all()
    now = _now()
    return jsonify([{
        "id": n.id, "text": n.text,
        "timestamp": n.timestamp.isoformat(),
        "expires_at": n.expires_at.isoformat() if n.expires_at else None,
        "likes": n.likes, "views": n.views, "reports": n.reports,
        "author_fp": getattr(n, "author_fp", None),
        "now": now.isoformat(),
    } for n in items]), 200

@api.post("/notes")
def create_note():
    if Note is None or db is None:
        return jsonify(error="backend_api_fallback_missing_models"), 500
    data = request.get_json(silent=True) or {}
    text = (data.get("text") or "").strip()
    if not text: return jsonify(error="text required"), 400
    try: hours = int(data.get("hours", 24))
    except Exception: hours = 24
    hours = min(168, max(1, hours))
    now = _now()
    try:
        n = Note(
            text=text, timestamp=now,
            expires_at=now + timedelta(hours=hours),
            author_fp=_fp()
        )
        db.session.add(n); db.session.commit()
        return jsonify({
            "id": n.id, "text": n.text,
            "timestamp": n.timestamp.isoformat(),
            "expires_at": n.expires_at.isoformat() if n.expires_at else None,
            "likes": n.likes, "views": n.views, "reports": n.reports,
            "author_fp": getattr(n, "author_fp", None),
            "now": now.isoformat(),
        }), 201
    except Exception as e:
        db.session.rollback()
        return jsonify(error="create_failed", detail=str(e)), 500
