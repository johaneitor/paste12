#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
cd "$(dirname "$0")"
ts=$(date +%s)

# 1) Backup
cp -p backend/models.py "backend/models.py.bak.$ts" 2>/dev/null || true

# 2) Reescritura completa del modelo
cat > backend/models.py <<'PY'
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
PY

# 3) Mini-migración: crea tablas e inserta columnas que falten
python - <<'PY'
from backend import create_app, db
app = create_app()
print("✅ create_app importado")

from sqlalchemy import text
with app.app_context():
    eng = db.engine
    dialect = eng.dialect.name
    print("DB:", dialect)

    if dialect == "sqlite":
        with eng.begin() as conn:
            cols = [r[1] for r in conn.exec_driver_sql("PRAGMA table_info(note)").fetchall()]
            def add(coldef):
                print("  - add:", coldef)
                conn.exec_driver_sql(f"ALTER TABLE note ADD COLUMN {coldef}")
            if "likes" not in cols:       add("likes INTEGER NOT NULL DEFAULT 0")
            if "views" not in cols:       add("views INTEGER NOT NULL DEFAULT 0")
            if "reports" not in cols:     add("reports INTEGER NOT NULL DEFAULT 0")
            if "user_token" not in cols:  add("user_token VARCHAR(64)")
            if "reported_by" not in cols: add("reported_by TEXT DEFAULT ''")
            conn.exec_driver_sql("CREATE INDEX IF NOT EXISTS ix_note_expires_at ON note (expires_at)")
        # tablas de logs (si no existen, create_all las crea)
        db.create_all()
    else:
        # Postgres
        with eng.begin() as conn:
            conn.exec_driver_sql("CREATE TABLE IF NOT EXISTS note (id INTEGER PRIMARY KEY)")
            conn.exec_driver_sql("ALTER TABLE note ADD COLUMN IF NOT EXISTS text VARCHAR(500) NOT NULL")
            conn.exec_driver_sql("ALTER TABLE note ADD COLUMN IF NOT EXISTS timestamp TIMESTAMPTZ")
            conn.exec_driver_sql("ALTER TABLE note ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ")
            conn.exec_driver_sql("ALTER TABLE note ADD COLUMN IF NOT EXISTS likes INTEGER NOT NULL DEFAULT 0")
            conn.exec_driver_sql("ALTER TABLE note ADD COLUMN IF NOT EXISTS views INTEGER NOT NULL DEFAULT 0")
            conn.exec_driver_sql("ALTER TABLE note ADD COLUMN IF NOT EXISTS reports INTEGER NOT NULL DEFAULT 0")
            conn.exec_driver_sql("ALTER TABLE note ADD COLUMN IF NOT EXISTS user_token VARCHAR(64)")
            conn.exec_driver_sql("ALTER TABLE note ADD COLUMN IF NOT EXISTS reported_by TEXT DEFAULT ''")
            conn.exec_driver_sql("CREATE INDEX IF NOT EXISTS ix_note_expires_at ON note (expires_at)")
        db.create_all()
    print("✅ mini-migración OK")
PY

# 4) Commit + push → fuerza redeploy
git add backend/models.py
git commit -m "fix(models): reescritura limpia + migración defensiva (likes/views/reports/logs)" || true
git push -u origin "$(git rev-parse --abbrev-ref HEAD)"
