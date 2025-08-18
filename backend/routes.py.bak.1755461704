from flask import Blueprint, request, jsonify
from datetime import datetime, timezone, timedelta
from .models import Note, LikeLog
from . import db

bp = Blueprint("api", __name__, url_prefix="/api")

def _fp():
    # token persistente enviado por el cliente; si no, IP
    tok = request.headers.get("X-Client-Token", "").strip()[:120]
    if not tok:
        tok = (request.headers.get("X-Forwarded-For", request.remote_addr) or "anon")[:120]
    return tok

@bp.get("/notes")
def get_notes():
    try:
        page = max(int(request.args.get("page", 1)), 1)
    except Exception:
        page = 1
    per_page = 10
    q = Note.query.order_by(Note.timestamp.desc())
    p = q.paginate(page=page, per_page=per_page, error_out=False)

    notes = [{
        "id": n.id,
        "text": n.text,
        "likes": getattr(n, "likes", 0) or 0,
        "views": getattr(n, "views", 0) or 0,
    } for n in p.items]

    return jsonify({"page": p.page, "total_pages": p.pages or 1, "notes": notes})

@bp.post("/notes")
def create_note():
    data = request.get_json(silent=True) or request.form or {}
    text = (data.get("text") or "").strip()
    if not text or len(text) > 500:
        return {"error": "Texto vacío o >500 caracteres"}, 400
    try:
        hours = int(data.get("expire_hours", 168))
        assert 1 <= hours <= 24*28
    except Exception:
        hours = 168
    expires_at = datetime.now(timezone.utc) + timedelta(hours=hours)
    note = Note(text=text, expires_at=expires_at)
    db.session.add(note)
    db.session.commit()
    return {"id": note.id}, 201

@bp.post("/notes/<int:note_id>/like")
def like_note(note_id):
    note = Note.query.get_or_404(note_id)
    fp = _fp()
    # ¿ya likeó?
    exists = LikeLog.query.filter_by(note_id=note_id, fingerprint=fp).first()
    if exists:
        return {"ok": False, "likes": note.likes, "reason": "already_liked"}, 200
    db.session.add(LikeLog(note_id=note_id, fingerprint=fp))
    note.likes = (note.likes or 0) + 1
    db.session.commit()
    return {"ok": True, "likes": note.likes}, 200

@bp.post("/notes/<int:note_id>/view")
def view_note(note_id):
    note = Note.query.get_or_404(note_id)
    note.views = (note.views or 0) + 1
    db.session.commit()
    return {"ok": True, "views": note.views}, 200
