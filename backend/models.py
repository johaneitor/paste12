from __future__ import annotations
from datetime import datetime, timedelta
from . import db

def default_exp():
    return datetime.utcnow() + timedelta(days=1)

class Note(db.Model):
    __tablename__ = "notes"
    id         = db.Column(db.Integer, primary_key=True)
    text       = db.Column(db.Text, nullable=False)
    timestamp  = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    expires_at = db.Column(db.DateTime, nullable=False, default=default_exp)
    likes      = db.Column(db.Integer, nullable=False, default=0)
    views      = db.Column(db.Integer, nullable=False, default=0)
    reports    = db.Column(db.Integer, nullable=False, default=0)
    author_fp  = db.Column(db.String(64), nullable=False, default="")
