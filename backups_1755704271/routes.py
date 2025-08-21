from __future__ import annotations
from .models import ViewLog
from flask import Blueprint, request, jsonify, current_app
from datetime import datetime, timezone, timedelta
from sqlalchemy.exc import IntegrityError
from . import db, limiter
from .models import Note, LikeLog, ReportLog

bp = Blueprint("api", __name__, url_prefix="/api")

def _now():
    return datetime.now(timezone.utc)

def _fp() -> str:
    # Lo más estable posible para identificar cliente
    return (
        request.headers.get("X-Client-Fingerprint")
        or request.headers.get("X-User-Token")
        or request.cookies.get("p12_fp")
        or request.headers.get("CF-Connecting-IP")
        or request.headers.get("X-Forwarded-For", "").split(",")[0].strip()
        or request.remote_addr
        or "anon"
    )

def _note_json(n: Note) -> dict:
    now = _now()
    rem = max(0, int((n.expires_at - now).total_seconds())) if getattr(n, "expires_at", None) else 0
    return {
        "id": n.id,
        "text": n.text,
        "timestamp": (n.timestamp.isoformat() if getattr(n, "timestamp", None) else None),
        "expires_at": (n.expires_at.isoformat() if getattr(n, "expires_at", None) else None),
        "remaining": rem,
        "likes": int(getattr(n, "likes", 0) or 0),
        "views": int(getattr(n, "views", 0) or 0),
        "reports": int(getattr(n, "reports", 0) or 0),
    }

def _per_page():
    import os
    try:
        v = int(os.getenv("PER_PAGE_DEFAULT", "10"))
    except Exception:
        v = 10
    max_v = int(os.getenv("MAX_PAGE_SIZE", "10"))
    return max(1, min(v, max_v))

@bp.get("/notes")
def list_notes():
    now = datetime.now(timezone.utc)
    try:
        page = max(1, int(request.args.get("page", 1)))
    except Exception:
        page = 1
    try:
        page_size = int(os.getenv("PAGE_SIZE", "20"))
    except Exception:
        page_size = 20
    page_size = max(10, min(page_size, 100))  # clamp 10..100

    q = Note.query.filter(Note.expires_at > now).order_by(Note.timestamp.desc())
    items = q.offset((page-1)*page_size).limit(page_size).all()
    has_more = len(items) == page_size

    return jsonify({
        "page": page,
        "page_size": page_size,
        "has_more": has_more,
        "notes": [_note_json(n, now) for n in items],
    })

@bp.post("/notes")
@limiter.limit("1 per 10 seconds", key_func=_rate_key)
@limiter.limit("500 per day", key_func=_rate_key)
def create_note():
    data = request.get_json(silent=True) or {}
    text = (data.get("text") or "").strip()
    try:
        hours = int(data.get("hours", 12))
    except Exception:
        hours = 12
    hours = max(1, min(hours, 24*7))  # entre 1h y 7 días

    if not text:
        return jsonify({"error": "text is required"}), 400

    now = _now()
    n = Note(
        text=text,
        timestamp=now,
        expires_at=now + timedelta(hours=hours),
    )
    db.session.add(n)
    db.session.commit()
    return jsonify({"ok": True, "id": n.id, "note": _note_json(n)}), 201

@bp.post("/notes/<int:note_id>/like")
def like_note(note_id: int):
    fp = _fp()
    n = Note.query.get_or_404(note_id)
    try:
        db.session.add(LikeLog(note_id=note_id, fingerprint=fp))
        n.likes = int(n.likes or 0) + 1
        db.session.commit()
        return jsonify({"likes": int(n.likes or 0), "already_liked": False})
    except IntegrityError:
        db.session.rollback()
        # ya likeó antes
        return jsonify({"likes": int(n.likes or 0), "already_liked": True})

@bp.post("/notes/<int:note_id>/view")
def view_note(note_id: int):
    n = Note.query.get_or_404(note_id)
    fp = request.headers.get("X-Client-Fingerprint") or request.cookies.get("fp") or request.remote_addr or "anon"
    today = datetime.now(timezone.utc).date()
    counted = False
    try:
        db.session.add(ViewLog(note_id=note_id, fingerprint=fp, view_date=today))
        db.session.flush()
        n.views = (n.views or 0) + 1
        db.session.commit()
        counted = True
    except IntegrityError:
        db.session.rollback()
    return jsonify({"views": int(n.views or 0), "counted": counted})

@bp.post("/notes/<int:note_id>/report")
def report_note(note_id: int):
    fp = _fp()
    n = Note.query.get_or_404(note_id)
    try:
        db.session.add(ReportLog(note_id=note_id, fingerprint=fp))
        n.reports = int(n.reports or 0) + 1
        if n.reports >= 5:
            # borrar la nota
            db.session.delete(n)
            db.session.commit()
            return jsonify({"deleted": True, "reports": 0, "already_reported": False})
        db.session.commit()
        return jsonify({"deleted": False, "reports": int(n.reports or 0), "already_reported": False})
    except IntegrityError:
        db.session.rollback()
        # ya reportó
        return jsonify({"deleted": False, "reports": int(n.reports or 0), "already_reported": True})

@bp.get("/health")
def health():
    return jsonify({"ok": True, "ts": _now().isoformat()})
