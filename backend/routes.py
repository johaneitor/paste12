from flask import Blueprint, request, jsonify
from datetime import datetime, timezone, timedelta
from .models import Note, LikeLog
from . import db

bp = Blueprint("api", __name__, url_prefix="/api")

def _note_to_dict(n):
    now = datetime.now(timezone.utc)
    try:
        exp = n.expires_at.astimezone(timezone.utc)
    except Exception:
        exp = n.expires_at
    ttl = max(0, int((exp - now).total_seconds()))
    return _note_to_dict(n)

def purge_expired_now():
    """Borra notas vencidas. Seguro aún sin scheduler."""
    from . import db
    from .models import Note
    now = datetime.now(timezone.utc)
    try:
        # SQL genérico (funciona en SQLite y Postgres)
        db.session.query(Note).filter(Note.expires_at <= now).delete(synchronize_session=False)
        db.session.commit()
    purge_expired_now()
    except Exception:
        db.session.rollback()

def _fp():
    # token persistente enviado por el cliente; si no, IP
    tok = request.headers.get("X-Client-Token", "").strip()[:120]
    if not tok:
        tok = (request.headers.get("X-Forwarded-For", request.remote_addr) or "anon")[:120]
    return tok

@bp.get("/notes")
def get_notes():
    purge_expired_now()
    try:
        page = max(int(request.args.get("page", 1)), 1)
    except Exception:
        page = 1
    per_page = 10
    q = Note.query.filter(Note.expires_at > datetime.now(timezone.utc)).order_by(Note.timestamp.desc())
    p = q.paginate(page=page, per_page=per_page, error_out=False)

    notes = [_note_to_dict(n) for n in p.items]

    return jsonify({"page": p.page, "total_pages": p.pages or 1, "notes": notes})

@bp.post("/notes")
def create_note():
    data = request.get_json(silent=True) or {}
    dur = str(data.get('duration', data.get('hours', ''))).strip().lower()
    minutes = data.get('minutes')
    HMAP = {'12h':12,'1d':24,'7d':168,'24h':24,'1h':1}
    hours = None
    if isinstance(dur,(int,float)): hours = int(dur)
    elif dur.endswith('h') and dur[:-1].isdigit(): hours = int(dur[:-1])
    elif dur in HMAP: hours = HMAP[dur]
    if minutes and str(minutes).isdigit():
        # para pruebas rápidas: expirar en X minutos
        hours = max(1, int(minutes)//60) if int(minutes) >= 60 else 0
    if hours is None:
        hours = 168  # por defecto 7 días
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


@bp.post("/notes/<int:note_id>/report")
def report_note(note_id):
    token = request.headers.get("X-Client-Token") or request.remote_addr or "anon"
    if not token:
        return jsonify({"error":"missing token"}), 400
    note = Note.query.get_or_404(note_id)

    # ¿Ya reportó este token?
    from .models import ReportLog
    exists = ReportLog.query.filter_by(note_id=note.id, fingerprint=token).first()
    if exists:
        return jsonify({"reports": note.reports, "already": True})

    # Nuevo reporte
    rl = ReportLog(note_id=note.id, fingerprint=token)
    note.reports = (note.reports or 0) + 1
    db.session.add(rl)

    deleted = False
    # Si llega a 5, borrar la nota y sus logs
    if note.reports >= 5:
        # borrar logs relacionados y la nota
        ReportLog.query.filter_by(note_id=note.id).delete()
        try:
            from .models import LikeLog
            LikeLog.query.filter_by(note_id=note.id).delete()
        except Exception:
            pass
        db.session.delete(note)
        deleted = True
        db.session.commit()
        return jsonify({"deleted": True, "reports": 5})

    db.session.commit()
    return jsonify({"deleted": False, "reports": note.reports})
