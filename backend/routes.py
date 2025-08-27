from __future__ import annotations

import os, hashlib
from datetime import datetime, timedelta
from flask import Blueprint, request, jsonify
from backend import db

# Import del modelo Note
try:
    from backend.models import Note
except Exception as e:  # mostramos el error al golpear endpoints
    Note = None
    _import_error = e
else:
    _import_error = None

# Un único blueprint llamado "api"
bp = Blueprint("api", __name__)

def _now() -> datetime:
    # Naive UTC (compatible con la mayoría de definiciones típicas de modelos)
    return datetime.utcnow()

def _fp() -> str:
    try:
        ip = request.headers.get("X-Forwarded-For","") or request.headers.get("CF-Connecting-IP","") or (request.remote_addr or "")
        ua = request.headers.get("User-Agent","")
        salt = os.environ.get("FP_SALT","")
        return hashlib.sha256(f"{ip}|{ua}|{salt}".encode()).hexdigest()[:32]
    except Exception:
        return "noctx"

def _note_json(n: "Note", now: datetime | None = None) -> dict:
    now = now or _now()
    return {
        "id": n.id,
        "text": n.text,
        "timestamp": n.timestamp.isoformat() if hasattr(n.timestamp, "isoformat") else n.timestamp,
        "expires_at": n.expires_at.isoformat() if hasattr(n.expires_at, "isoformat") else n.expires_at,
        "likes": getattr(n, "likes", 0),
        "views": getattr(n, "views", 0),
        "reports": getattr(n, "reports", 0),
        "author_fp": getattr(n, "author_fp", None),
        "now": now.isoformat(),
    }

@bp.route("/health", methods=["GET"])
def health():
    return jsonify({"ok": True})

@bp.route("/notes", methods=["GET"])
def list_notes():
    if Note is None:
        return jsonify({"ok": False, "error": f"Note not importable: {_import_error!r}"}), 500
    try:
        page = int(request.args.get("page", 1))
    except Exception:
        page = 1
    page = max(1, page)
    per_page = 20
    q = Note.query.order_by(Note.timestamp.desc())
    items = q.limit(per_page).offset((page - 1) * per_page).all()
    now = _now()
    return jsonify([_note_json(n, now) for n in items]), 200

@bp.route("/notes", methods=["POST"])
def create_note():
    if Note is None:
        return jsonify({"ok": False, "error": f"Note not importable: {_import_error!r}"}), 500
    try:
        data = request.get_json(silent=True) or {}
        text = (data.get("text") or "").strip()
        if not text:
            return jsonify({"error": "text required"}), 400
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
    except Exception as e:
        db.session.rollback()
        return jsonify({"error":"create_failed", "detail": str(e)}), 500

@bp.route("/notes/<int:note_id>/like", methods=["POST"])
def like_note(note_id: int):
    if Note is None:
        return jsonify({"ok": False, "error": f"Note not importable: {_import_error!r}"}), 500
    n = Note.query.get(note_id)
    if not n:
        return jsonify({"error":"not_found"}), 404
    try:
        n.likes = int(getattr(n, "likes", 0)) + 1
        db.session.commit()
        return jsonify({"ok": True, "likes": n.likes, "id": n.id}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"error":"like_failed", "detail": str(e)}), 500
