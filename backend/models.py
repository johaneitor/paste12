from __future__ import annotations
from datetime import datetime, timezone, date
from . import db

def _utcnow():
    return datetime.now(timezone.utc)

class Note(db.Model):
    __tablename__ = "note"
    id = db.Column(db.Integer, primary_key=True)
    text = db.Column(db.Text, nullable=False)
    timestamp = db.Column(db.DateTime(timezone=True), default=_utcnow, nullable=False, index=True)
    expires_at = db.Column(db.DateTime(timezone=True), nullable=False, index=True)
    likes = db.Column(db.Integer, nullable=False, default=0)
    views = db.Column(db.Integer, nullable=False, default=0)
    reports = db.Column(db.Integer, nullable=False, default=0)
class LikeLog(db.Model):
    __tablename__ = "like_log"
    id = db.Column(db.Integer, primary_key=True)
    note_id = db.Column(db.Integer, db.ForeignKey("note.id", ondelete="CASCADE"), nullable=False, index=True)
    fingerprint = db.Column(db.String(128), nullable=False)
    created_at = db.Column(db.DateTime(timezone=True), default=_utcnow, nullable=False)
    __table_args__ = (db.UniqueConstraint("note_id", "fingerprint", name="uq_like_note_fp"),)

class ReportLog(db.Model):
    __tablename__ = "report_log"
    id = db.Column(db.Integer, primary_key=True)
    note_id = db.Column(db.Integer, db.ForeignKey("note.id", ondelete="CASCADE"), nullable=False, index=True)
    fingerprint = db.Column(db.String(128), nullable=False)
    created_at = db.Column(db.DateTime(timezone=True), default=_utcnow, nullable=False)
    __table_args__ = (db.UniqueConstraint("note_id", "fingerprint", name="uq_report_note_fp"),)

class ViewLog(db.Model):
    __tablename__ = "view_log"
    id = db.Column(db.Integer, primary_key=True)
    note_id = db.Column(db.Integer, db.ForeignKey("note.id", ondelete="CASCADE"), nullable=False, index=True)
    fingerprint = db.Column(db.String(128), nullable=False, index=True)
    view_date = db.Column(db.Date, nullable=False, index=True)  # 1 vista/día/nota/fp
    created_at = db.Column(db.DateTime(timezone=True), default=_utcnow, nullable=False, index=True)
    __table_args__ = (db.UniqueConstraint("note_id", "fingerprint", "view_date", name="uq_view_note_fp_day"),)
