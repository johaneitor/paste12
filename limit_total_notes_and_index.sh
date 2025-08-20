#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
ts=$(date +%s)
cd "$(dirname "$0")"

echo "🔧 Limite global + índices (cap de notas)"

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
if "import os" not in code:
    code = code.replace("from datetime import datetime, timezone, timedelta",
                        "from datetime import datetime, timezone, timedelta\nimport os")

# Asegurar LikeLog/ReportLog
if "LikeLog" not in code or "ReportLog" not in code:
    code = re.sub(r"from\s+\.\s*models\s+import\s+Note",
                  "from .models import Note, LikeLog, ReportLog",
                  code)

# Helper para cap global (idempotente)
if "_enforce_global_cap" not in code:
    inject = r"""
def _enforce_global_cap():
    """
    Enforcea MAX_NOTES (por env) borrando las notas más viejas con sus logs.
    """
    from flask import current_app
    try:
        cap = int(os.getenv("MAX_NOTES", "20000"))
    except Exception:
        cap = 20000
    if cap <= 0:
        return
    # Conteo rápido
    from . import db
    total = db.session.query(Note.id).count()
    if total < cap:
        return
    to_delete = total - cap + 1
    # Ids más viejas por timestamp
    old_ids = [row[0] for row in db.session.query(Note.id)
                              .order_by(Note.timestamp.asc())
                              .limit(to_delete).all()]
    if not old_ids:
        return
    # Borrar logs primero por FK
    db.session.query(LikeLog).filter(LikeLog.note_id.in_(old_ids)).delete(synchronize_session=False)
    db.session.query(ReportLog).filter(ReportLog.note_id.in_(old_ids)).delete(synchronize_session=False)
    db.session.query(Note).filter(Note.id.in_(old_ids)).delete(synchronize_session=False)
    db.session.commit()
"""
    # Insertar tras imports
    m = re.search(r"(?:^|\n)from\s+\.\s*models\s+import[^\n]+\n", code)
    pos = m.end() if m else 0
    code = code[:pos] + inject + code[pos:]

# En el endpoint de creación, purgar exp/ cap antes de insertar
# Buscamos @bp.post("/notes") y la función
m = re.search(r"@bp\.post\([\"\']/notes[\"\']\)\s*def\s+(\w+)\s*\([^)]*\):", code)
if not m:
    raise SystemExit("❌ No se encontró endpoint POST /notes")
start = m.end()
# Insertamos secuencia justo después del def ...:
#  - now = datetime.now(...)
#  - purge expiradas
#  - enforce cap
insertion = r"""
    # --- housekeeping: purgar expiradas + cap global ---
    now = datetime.now(timezone.utc)
    from . import db
    db.session.query(Note).filter(Note.expires_at <= now).delete(synchronize_session=False)
    db.session.commit()
    _enforce_global_cap()
"""
# Solo si no está ya
func_head_slice = code[start:start+400]
if "_enforce_global_cap()" not in func_head_slice:
    code = code[:start] + insertion + code[start:]

p.write_text(code)
print("✓ routes.py: enforce de cap + purge expiradas antes de crear")
PY

# --- Patch __init__.py: crear índices si no existen en migrate_min ---
python - <<'PY'
from pathlib import Path
import re

p = Path("backend/__init__.py")
code = p.read_text()

# Asegurar import text()
if "from sqlalchemy import text" not in code:
    code = code.replace("\nfrom apscheduler", "\nfrom sqlalchemy import text\nfrom apscheduler")

# Insertar/actualizar migrate_min
if "def migrate_min(" not in code:
    code += """

def migrate_min(app):
    from flask import current_app
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
                current_app.logger.warning(f"migrate_min: {e}")
            except Exception:
                print("migrate_min warn:", e)
"""
else:
    # Agregar las CREATE INDEX IF NOT EXISTS si no están
    code = re.sub(
        r"(def\s+migrate_min\s*\(app\):[\s\S]*?with\s+db\.engine\.begin\(\)\s+as\s+conn:\s*)",
        r"\1\n                conn.execute(text(\"CREATE INDEX IF NOT EXISTS ix_note_expires_at ON note (expires_at)\"))\n                conn.execute(text(\"CREATE INDEX IF NOT EXISTS ix_note_exp_ts ON note (expires_at, timestamp)\"))\n                conn.execute(text(\"CREATE INDEX IF NOT EXISTS ix_note_ts_desc ON note (timestamp DESC)\"))\n",
        code,
        count=1,
        flags=re.M
    )

Path("backend/__init__.py").write_text(code)
print("✓ __init__.py: migrate_min con índices IF NOT EXISTS")
PY

# Validación rápida de sintaxis
python -m py_compile backend/routes.py backend/__init__.py

# Commit + push
git add backend/routes.py backend/__init__.py
git commit -m "feat(cap): limitar total de notas (MAX_NOTES) y crear índices para feed; purge expiradas antes de crear" || true
git push -u origin "$(git rev-parse --abbrev-ref HEAD)"

echo "🚀 Listo. Ahora define MAX_NOTES en Render (Environment) si querés otro valor; por defecto 20000."
