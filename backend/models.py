from datetime import datetime, timezone, timedelta
from . import db

class Note(db.Model):
    __tablename__ = "note"

    id          = db.Column(db.Integer, primary_key=True)
    text        = db.Column(db.String(500), nullable=False)
    timestamp   = db.Column(db.DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    # Por si no se pasa explícitamente al crear:
    expires_at  = db.Column(db.DateTime(timezone=True), default=lambda: datetime.now(timezone.utc) + timedelta(days=7))

    # Métricas / moderación
    likes       = db.Column(db.Integer, default=0)
    views       = db.Column(db.Integer, default=0)
    reports     = db.Column(db.Integer, default=0)
    user_token  = db.Column(db.String(64), index=True)     # opcional (para limitar por cliente)
    reported_by = db.Column(db.Text, default="")           # opcional (lista de tokens)

    def __repr__(self) -> str:  # solo para debug
        return f"<Note id={self.id}>"
