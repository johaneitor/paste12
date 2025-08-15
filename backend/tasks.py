from datetime import datetime, timezone
from .models import Note
from . import db

def purge_expired(app):
    with app.app_context():
        Note.query.filter(Note.expires_at <= datetime.now(timezone.utc)).delete()
        db.session.commit()
