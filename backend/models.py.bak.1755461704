from datetime import datetime, timezone, timedelta
from . import db

class Note(db.Model):
    views = db.Column(db.Integer, default=0)
    likes = db.Column(db.Integer, default=0)
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


class LikeLog(db.Model):
    __tablename__ = "like_log"
    id = db.Column(db.Integer, primary_key=True)
    note_id = db.Column(db.Integer, db.ForeignKey('note.id', ondelete='CASCADE'), nullable=False, index=True)
    fingerprint = db.Column(db.String(128), nullable=False)
    created_at = db.Column(db.DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    __table_args__ = (db.UniqueConstraint('note_id','fingerprint', name='uq_like_note_fp'),)
