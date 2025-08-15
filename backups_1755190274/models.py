from datetime import datetime, timezone, timedelta
from . import db

class Note(db.Model):
    id          = db.Column(db.Integer, primary_key=True)
    id          = db.Column(db.Integer, primary_key=True)
    text        = db.Column(db.String(500), nullable=False)
    timestamp   = db.Column(db.DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    expires_at  = db.Column(db.DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)+timedelta(days=7))
    reports     = db.Column(db.Integer, default=0)
    user_token  = db.Column(db.String(64), index=True)
    likes       = db.Column(db.Integer, default=0, nullable=False)
    views       = db.Column(db.Integer, default=0, nullable=False)
    reported_by = db.Column(db.Text, default="")
