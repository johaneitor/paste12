from flask import Blueprint, request, jsonify
from datetime import datetime, timezone, timedelta
from hashlib import sha256
from sqlalchemy.exc import IntegrityError

from .models import Note, LikeLog, ReportLog
from . import db, limiter

bp = Blueprint("api", __name__, url_prefix="/api")

def _serialize(n: Note):
    now = datetime.now(timezone.utc)
    rem = max(0, int((n.expires_at - now).total_seconds())) if n.expires_at else 0
    return {
        "id": n.id,
        "text": n.text,
        "timestamp": n.timestamp.isoformat() if n.timestamp else None,
        "expires_at": n.expires_at.isoformat() if n.expires_at else None,
        "remaining_seconds": rem,
        "likes": int(getattr(n, "likes", 0) or 0),
        "views": int(getattr(n, "views", 0) or 0),
        "reports": int(getattr(n, "reports", 0) or 0),
    }

def _fingerprint():
    # 1) token explícito
    tok = (request.headers.get('X-User-Token') or request.cookies.get('p12') or '').strip()
    if tok:
        return tok[:128]
    # 2) X-Forwarded-For (primer IP)
    xff = request.headers.get('X-Forwarded-For', '')
    if xff:
        ip = xff.split(',')[0].strip()
    else:
        ip = request.remote_addr or ''
    ua = request.headers.get('User-Agent', '')
    return sha256(f"{ip}|{ua}".encode('utf-8')).hexdigest()

    # 1) Preferir token de cliente
    tok = (request.headers.get("X-User-Token") or request.cookies.get("p12") or "").strip()
    if tok:
        return tok[:128]
    # 2) Huella derivada (IP+UA)
    ua = request.headers.get("User-Agent", "")
    ip = request.headers.get("X-Forwarded-For", request.remote_addr or "")
    return sha256(f"{ip}|{ua}".encode("utf-8")).hexdigest()


def _rate_key():
    tok = (request.headers.get('X-User-Token') or request.cookies.get('p12') or '').strip()
    if tok:
        return tok[:128]
    xff = request.headers.get('X-Forwarded-For','')
    ip = xff.split(',')[0].strip() if xff else (request.remote_addr or '')
    ua = request.headers.get('User-Agent','')
    return sha256(f"{ip}|{ua}".encode()).hexdigest()

@bp.get("/notes")
def get_notes():
    page = max(int(request.args.get("page", 1) or 1), 1)
    per_page = min(int(request.args.get("per_page", 10) or 10), 50)
    now = datetime.now(timezone.utc)
    q = Note.query.filter(Note.expires_at > now).order_by(Note.timestamp.desc())
    p = q.paginate(page=page, per_page=per_page, error_out=False)
    return jsonify({"items": [_serialize(n) for n in p.items], "page": p.page, "pages": p.pages, "total": p.total})

@bp.post("/notes")
@limiter.limit('1 per 10 seconds', key_func=_rate_key)
@limiter.limit('500 per day', key_func=_rate_key)
def create_note():
    data = request.get_json(silent=True) or {}
    text = (data.get("text") or "").strip()
    if not text:
        return jsonify({"error": "Texto requerido"}), 400

    dur = str(data.get("duration", "")).strip().lower()
    HMAP = {"12h":12, "1d":24, "24h":24, "7d":168}
    if isinstance(data.get("hours"), (int, float)) and data["hours"] > 0:
        hours = int(data["hours"])
    elif dur.endswith("h") and dur[:-1].isdigit():
        hours = int(dur[:-1])
    else:
        hours = HMAP.get(dur, 24*7)
    hours = max(1, min(hours, 24*30))

    now = datetime.now(timezone.utc)
    n = Note(text=text, timestamp=now, expires_at=now + timedelta(hours=hours))
    db.session.add(n)
    db.session.commit()
    return jsonify(_serialize(n)), 201

@bp.post("/notes/<int:note_id>/like")
def like_note(note_id: int):
    n = Note.query.get_or_404(note_id)
    fp = _fingerprint()

    # ¿ya likeó?
    if LikeLog.query.filter_by(note_id=n.id, fingerprint=fp).first():
        return jsonify({"likes": n.likes, "already_liked": True})

    try:
        db.session.add(LikeLog(note_id=n.id, fingerprint=fp))
        n.likes = (n.likes or 0) + 1
        db.session.commit()
        return jsonify({"likes": n.likes, "already_liked": False})
    except IntegrityError:
        db.session.rollback()
        n = Note.query.get(note_id)
        return jsonify({"likes": n.likes, "already_liked": True})

@bp.post("/notes/<int:note_id>/view")
def view_note(note_id: int):
    n = Note.query.get_or_404(note_id)
    n.views = (n.views or 0) + 1
    db.session.commit()
    return jsonify({"views": n.views})

@bp.post("/notes/<int:note_id>/report")
def report_note(note_id: int):
    n = Note.query.get_or_404(note_id)
    fp = _fingerprint()

    # ¿ya reportó?
    if ReportLog.query.filter_by(note_id=n.id, fingerprint=fp).first():
        return jsonify({"reports": n.reports, "already_reported": True, "deleted": False})

    try:
        db.session.add(ReportLog(note_id=n.id, fingerprint=fp))
        n.reports = (n.reports or 0) + 1
        if n.reports >= 5:
            db.session.delete(n)
            db.session.commit()
            return jsonify({"deleted": True, "reports": 0, "already_reported": False})
        db.session.commit()
        return jsonify({"deleted": False, "reports": n.reports, "already_reported": False})
    except IntegrityError:
        db.session.rollback()
        n = Note.query.get(note_id)
        return jsonify({"deleted": False, "reports": n.reports, "already_reported": True})
