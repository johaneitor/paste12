from __future__ import annotations
from datetime import datetime, timedelta
from sqlalchemy import func, UniqueConstraint
from . import db

class Note(db.Model):
    __tablename__ = "notes"
    id = db.Column(db.Integer, primary_key=True)
    text = db.Column(db.Text, nullable=False)
    timestamp = db.Column(db.DateTime, nullable=False, default=func.now())
    expires_at = db.Column(db.DateTime, nullable=True)
    likes = db.Column(db.Integer, nullable=False, default=0)
    views = db.Column(db.Integer, nullable=False, default=0)
    reports = db.Column(db.Integer, nullable=False, default=0)
    author_fp = db.Column(db.String(64), nullable=True)
    # Soft-delete (migración la añadirá si falta)
    deleted_at = db.Column(db.DateTime, nullable=True)

    def to_dict(self):
        return {
            "id": self.id,
            "text": self.text,
            "timestamp": (self.timestamp or datetime.utcnow()).isoformat(),
            "expires_at": self.expires_at.isoformat() if self.expires_at else None,
            "likes": self.likes,
            "views": self.views,
            "reports": self.reports,
            "author_fp": self.author_fp,
        }

    @staticmethod
    def default_ttl_hours() -> int:
        # 24h por defecto si no hay política distinta
        return 24

    @staticmethod
    def compute_expiry():
        return (datetime.utcnow() + timedelta(hours=Note.default_ttl_hours()))


class NoteReport(db.Model):
    __tablename__ = "note_report"
    id = db.Column(db.Integer, primary_key=True)
    note_id = db.Column(db.Integer, nullable=False, index=True)
    reporter_hash = db.Column(db.String(64), nullable=False)
    created_at = db.Column(db.DateTime, nullable=False, default=func.now())

    __table_args__ = (
        UniqueConstraint("note_id", "reporter_hash", name="uix_note_reporter"),
    )
