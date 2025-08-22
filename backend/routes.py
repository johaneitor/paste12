from __future__ import annotations
def _fp() -> str:
    return 'noctx'
from datetime import datetime, timedelta, timezone
from typing import Optional

from flask import Blueprint, jsonify, request
from backend.models import db, Note
bp = Blueprint("api", __name__)

def _now() -> datetime:
    return datetime.now(timezone.utc)

def _note_json(n: Note, now: Optional[datetime] = None) -> dict:
    if now is None:
        now = _now()
    return {
        "id": n.id,
        "text": n.text,
        "timestamp": n.timestamp.isoformat() if getattr(n, "timestamp", None) else None,
        "expires_at": n.expires_at.isoformat() if getattr(n, "expires_at", None) else None,
        "likes": getattr(n, "likes", 0),
        "views": getattr(n, "views", 0),
        "reports": getattr(n, "reports", 0),
    }

@bp.route("/health", methods=["GET"])
def health():
    return jsonify({"ok": True}), 200

@bp.route("/notes", methods=["GET"])
def list_notes():
    try:
        page = int(request.args.get("page", 1))
    except Exception:
        page = 1
    page = max(1, page)
    q = Note.query.order_by(Note.timestamp.desc())
    items = q.limit(20).offset((page - 1) * 20).all()
    return jsonify([_note_json(n, _now()) for n in items]), 200

@bp.route("/notes", methods=["POST"])
def create_note():
    from flask import request, jsonify
    from datetime import timedelta
    data = request.get_json(silent=True) or {}
    text = (data.get('text') or '').strip()
    if not text:
        return jsonify({'error':'text required'}), 400
    try:
        hours = int(data.get('hours', 24))
    except Exception:
        hours = 24
    hours = min(168, max(1, hours))
    now = _now()
    try:
        n = Note(text=text, timestamp=now, expires_at=now + timedelta(hours=hours),
            author_fp=_fp(),)
        try:
            # Fallback si el hook no setea author_fp
            if not getattr(n, 'author_fp', None):
                n.author_fp = _fp()
        except Exception:
            pass
        db.session.add(n)
        db.session.commit()
        return jsonify(_note_json(n, now)), 201
    except Exception as e:
        db.session.rollback()
        import traceback
        tb = traceback.format_exc()
        try:
            from flask import current_app
            current_app.logger.error('create_note failed: %s', tb)
        except Exception:
            pass
        return jsonify({'error':'create_failed','detail':str(e),'trace':tb}), 500
@bp.route("/notes/<int:note_id>/like", methods=["POST"])
def like_note(note_id: int):
    n = Note.query.get_or_404(note_id)
    n.likes = (n.likes or 0) + 1
    db.session.commit()
    return jsonify({"ok": True, "likes": n.likes}), 200

@bp.route("/notes/<int:note_id>/report", methods=["POST"])
def report_note(note_id: int):
    n = Note.query.get_or_404(note_id)
    n.reports = (n.reports or 0) + 1
    db.session.commit()
    return jsonify({"ok": True, "reports": n.reports}), 200

@bp.route("/notes/<int:note_id>/view", methods=["POST"])
def view_note(note_id: int):
    n = Note.query.get_or_404(note_id)
    n.views = (n.views or 0) + 1
    db.session.commit()
    return jsonify({"ok": True, "views": n.views}), 200
