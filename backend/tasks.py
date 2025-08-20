from datetime import datetime, timezone
from .models import Note

def enforce_global_cap(app):
    # Borra notas más viejas si superan MAX_NOTES (env; por defecto 20000).
    import os
    from . import db
    from .models import Note, LikeLog, ReportLog
    try:
        cap = int(os.getenv("MAX_NOTES", "20000") or 0)
    except Exception:
        cap = 20000
    if cap <= 0:
        return 0
    with app.app_context():
        total = db.session.query(Note.id).count()
        if total <= cap:
            return 0
        to_delete = total - cap
        old_ids = [r[0] for r in db.session.query(Note.id).order_by(Note.timestamp.asc()).limit(to_delete).all()]
        if not old_ids:
            return 0
        db.session.query(LikeLog).filter(LikeLog.note_id.in_(old_ids)).delete(synchronize_session=False)
        db.session.query(ReportLog).filter(ReportLog.note_id.in_(old_ids)).delete(synchronize_session=False)
        db.session.query(Note).filter(Note.id.in_(old_ids)).delete(synchronize_session=False)
        db.session.commit()
        return to_delete

from . import db

def purge_expired(app):
    
    try:
        enforce_global_cap(app)
    except Exception:
        pass
with app.app_context():
        Note.query.filter(Note.expires_at <= datetime.now(timezone.utc)).delete()
        db.session.commit()
