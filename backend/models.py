from datetime import datetime, timezone, timedelta
from . import db

class Note(db.Model):
    __tablename__ = "note"
    id          = db.Column(db.Integer, primary_key=True)
    text        = db.Column(db.String(500), nullable=False)
    timestamp   = db.Column(db.DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    expires_at  = db.Column(db.DateTime(timezone=True), index=True, nullable=False)
    likes       = db.Column(db.Integer, default=0, nullable=False)
    views       = db.Column(db.Integer, default=0, nullable=False)
    reports     = db.Column(db.Integer, default=0, nullable=False)
    user_token  = db.Column(db.String(64), index=True)
    reported_by = db.Column(db.Text, default="")

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        if not getattr(self, "expires_at", None):
            self.expires_at = datetime.now(timezone.utc) + timedelta(days=7)

    def __repr__(self) -> str:
        return f"<Note id={self.id}>"

# Un like por huella y nota
class LikeLog(db.Model):
    __tablename__ = "like_log"
    id          = db.Column(db.Integer, primary_key=True)
    note_id     = db.Column(db.Integer, db.ForeignKey("note.id", ondelete="CASCADE"), nullable=False, index=True)
    fingerprint = db.Column(db.String(128), nullable=False)
    created_at  = db.Column(db.DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    __table_args__ = (db.UniqueConstraint("note_id", "fingerprint", name="uq_like_note_fp"),)

# Un reporte por huella y nota
class ReportLog(db.Model):
    __tablename__ = "report_log"
    id          = db.Column(db.Integer, primary_key=True)
    note_id     = db.Column(db.Integer, db.ForeignKey("note.id", ondelete="CASCADE"), nullable=False, index=True)
    fingerprint = db.Column(db.String(128), nullable=False)
    created_at  = db.Column(db.DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    __table_args__ = (db.UniqueConstraint("note_id", "fingerprint", name="uq_report_note_fp"),)




class ViewLog(db.Model):
    __tablename__ = "view_log"
    id = db.Column(db.Integer, primary_key=True)
    note_id = db.Column(db.Integer, db.ForeignKey("note.id", ondelete="CASCADE"), nullable=False, index=True)
    fingerprint = db.Column(db.String(128), nullable=False, index=True)
    view_date = db.Column(db.Date, nullable=False, index=True)  # día UTC
    created_at = db.Column(db.DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False, index=True)
    __table_args__ = (
        db.UniqueConstraint("note_id", "fingerprint", "view_date", name="uq_view_note_fp_day"),
    )

