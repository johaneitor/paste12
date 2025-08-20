#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
ts=$(date +%s)
cd "$(dirname "$0")"

echo "🔧 Limite global + índices (cap de notas) — FIX"

# Backups
cp -p backend/routes.py "backend/routes.py.bak.$ts" 2>/dev/null || true
cp -p backend/__init__.py "backend/__init__.py.bak.$ts" 2>/dev/null || true

# --- Patch routes.py: enforce cap global antes de crear ---
python - <<'PY'
from pathlib import Path
import re

p = Path("backend/routes.py")
code = p.read_text()

# Asegurar imports
if "from .models import Note" in code and ("LikeLog" not in code or "ReportLog" not in code):
    code = code.replace("from .models import Note", "from .models import Note, LikeLog, ReportLog")

# Inyectar helper sin docstring
if "_enforce_global_cap" not in code:
    inject = r"""
def _enforce_global_cap():
    # Enforcea MAX_NOTES (por env) borrando las notas más viejas con sus logs.
    import os
    from . import db
    try:
        cap = int(os.getenv("MAX_NOTES", "20000"))
    except Exception:
        cap = 20000
    if cap <= 0:
        return
    total = db.session.query(Note.id).count()
    if total < cap:
        return
    to_delete = total - cap + 1
    old_ids = [row[0] for row in db.session.query(Note.id)
                              .order_by(Note.timestamp.asc())
                              .limit(to_delete).all()]
    if not old_ids:
        return
    db.session.query(LikeLog).filter(LikeLog.note_id.in_(old_ids)).delete(synchronize_session=False)
    db.session.query(ReportLog).filter(ReportLog.note_id.in_(old_ids)).delete(synchronize_session=False)
    db.session.query(Note).filter(Note.id.in_(old_ids)).delete(synchronize_session=False)
    db.session.commit()
"""
    # Insertarlo tras la línea de imports de modelos
    m = re.search(r"(?:^|\n)from\s+\.\s*models\s+import[^\n]+\n", code)
    pos = m.end() if m else 0
    code = code[:pos] + inject + code[pos:]

# Hook en POST /notes: purga expiradas + cap (si no estuviera)
m = re.search(r"@bp\.post\([\"']/notes[\"']\)\s*def\s+\w+\s*\([^)]*\):", code)
if not m:
    raise SystemExit("❌ No se encontró endpoint POST /notes")
start = m.end()
head = code[start:start+500]
insertion = r"""
    # --- housekeeping: purgar expiradas + cap global ---
    now = datetime.now(timezone.utc)
    from . import db
    db.session.query(Note).filter(Note.expires_at <= now).delete(synchronize_session=False)
    db.session.commit()
    _enforce_global_cap()
"""
if "_enforce_global_cap()" not in head:
    code = code[:start] + insertion + code[start:]

p.write_text(code)
print("✓ routes.py: helper + housekeeping insertados")
PY

# --- Patch __init__.py: migrate_min con índices ---
python - <<'PY'
from pathlib import Path, PurePosixPath
import re

p = Path("backend/__init__.py")
code = p.read_text()

if "from sqlalchemy import text" not in code:
    code = code.replace("\nfrom apscheduler", "\nfrom sqlalchemy import text\nfrom apscheduler")

if "def migrate_min(" not in code:
    code += """

def migrate_min(app):
    from . import db
    with app.app_context():
        try:
            db.create_all()
            with db.engine.begin() as conn:
                conn.execute(text("CREATE INDEX IF NOT EXISTS ix_note_expires_at ON note (expires_at)"))
                conn.execute(text("CREATE INDEX IF NOT EXISTS ix_note_exp_ts ON note (expires_at, timestamp)"))
                conn.execute(text("CREATE INDEX IF NOT EXISTS ix_note_ts_desc ON note (timestamp DESC)"))
        except Exception as e:
            try:
                app.logger.warning(f"migrate_min: {e}")
            except Exception:
                print("migrate_min warn:", e)
"""
else:
    code = re.sub(
        r"(with\s+db\.engine\.begin\(\)\s+as\s+conn:\s*)",
        r"\1\n                conn.execute(text(\"CREATE INDEX IF NOT EXISTS ix_note_expires_at ON note (expires_at)\"))\n                conn.execute(text(\"CREATE INDEX IF NOT EXISTS ix_note_exp_ts ON note (expires_at, timestamp)\"))\n                conn.execute(text(\"CREATE INDEX IF NOT EXISTS ix_note_ts_desc ON note (timestamp DESC)\"))\n",
        code, count=1
    )

p.write_text(code)
print("✓ __init__.py: migrate_min con índices IF NOT EXISTS")
PY

# Validación
python -m py_compile backend/routes.py backend/__init__.py

# Commit + push
git add backend/routes.py backend/__init__.py
git commit -m "feat(cap): limitar total de notas (MAX_NOTES) + índices (expires_at, expires_at+timestamp, timestamp DESC)" || true
git push -u origin "$(git rev-parse --abbrev-ref HEAD)"

echo "🚀 Enviado. Define MAX_NOTES en Render (Environment) si querés otro valor; default 20000."
