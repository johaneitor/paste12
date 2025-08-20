#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
ts=$(date +%s)
cd "$(dirname "$0")"
echo "🔧 Enforcing MAX_NOTES cap + índices + hooks (boot/purge/get/post)"

backup(){ cp -p "$1" "$1.bak.$ts" 2>/dev/null || true; }

# ---- 1) tasks.py: agregar enforce_global_cap() y llamarla desde purge_expired() ----
backup backend/tasks.py
python - <<'PY'
from pathlib import Path, re
p = Path("backend/tasks.py")
code = p.read_text()

# Asegurar presencia de enforce_global_cap()
if "def enforce_global_cap(" not in code:
    # Insertar justo al inicio (después de imports si existen)
    inspos = 0
    m = re.search(r"(?:^|\n)(from\s+.*|import\s+.*)\n(?:from\s+.*|import\s+.*\n)*", code)
    if m: inspos = m.end()
    block = r"""

def enforce_global_cap(app):
    # Borra notas más viejas si superan MAX_NOTES (env; por defecto 20000).
    import os
    from . import db
    from .models import Note, LikeLog, ReportLog
    try:
        cap = int(os.getenv("MAX_NOTES", "20000") or 0)
    except Exception:
        cap = 20000
    if cap <= 0:
        return 0
    with app.app_context():
        total = db.session.query(Note.id).count()
        if total <= cap:
            return 0
        to_delete = total - cap
        old_ids = [r[0] for r in db.session.query(Note.id).order_by(Note.timestamp.asc()).limit(to_delete).all()]
        if not old_ids:
            return 0
        db.session.query(LikeLog).filter(LikeLog.note_id.in_(old_ids)).delete(synchronize_session=False)
        db.session.query(ReportLog).filter(ReportLog.note_id.in_(old_ids)).delete(synchronize_session=False)
        db.session.query(Note).filter(Note.id.in_(old_ids)).delete(synchronize_session=False)
        db.session.commit()
        return to_delete
"""
    code = code[:inspos] + block + code[inspos:]

# Hacer que purge_expired(app) llame a enforce_global_cap(app)
pm = re.search(r"def\s+purge_expired\s*\(\s*app\s*\)\s*:\s*", code)
if pm:
    body_start = pm.end()
    # Si ya existe llamada, no duplicar
    if "enforce_global_cap(app)" not in code[body_start:body_start+400]:
        code = code[:body_start] + "\n    try:\n        enforce_global_cap(app)\n    except Exception:\n        pass\n" + code[body_start:]

Path("backend/tasks.py").write_text(code)
print("✓ tasks.py listo (enforce_global_cap + hook en purge_expired)")
PY

# ---- 2) __init__.py: llamar enforce_cap al boot y asegurar índices ----
backup backend/__init__.py
python - <<'PY'
from pathlib import Path, re
p = Path("backend/__init__.py")
code = p.read_text()

# Imports necesarios
if "import os" not in code:
    code = code.replace("from datetime import", "import os\nfrom datetime import")
if "from sqlalchemy import text" not in code:
    code = code.replace("\nfrom apscheduler", "\nfrom sqlalchemy import text\nfrom apscheduler")

# migrate_min: índices IF NOT EXISTS
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
    # Insertar 1 vez dentro del primer with db.engine.begin()
    code = re.sub(
        r"(with\s+db\.engine\.begin\(\)\s+as\s+conn:\s*)\n",
        r"\1\n                conn.execute(text(\"CREATE INDEX IF NOT EXISTS ix_note_expires_at ON note (expires_at)\"))\n                conn.execute(text(\"CREATE INDEX IF NOT EXISTS ix_note_exp_ts ON note (expires_at, timestamp)\"))\n                conn.execute(text(\"CREATE INDEX IF NOT EXISTS ix_note_ts_desc ON note (timestamp DESC)\"))\n",
        code, count=1
    )

# En create_app(): llamar enforce_cap al boot (si ENFORCE_CAP_ON_BOOT=1)
m = re.search(r"def\s+create_app\s*\([^)]*\):", code)
if m:
    start = m.end()
    # Buscar lugar razonable tras inicializar app/db (antes de return app)
    ret = re.search(r"\n\s*return\s+app\b", code[start:], re.M)
    insert_at = start + (ret.start() if ret else 0)
    payload = """
    # Enforce cap al boot (una vez) si está habilitado
    try:
        from .tasks import enforce_global_cap as _egc
        if os.getenv("ENFORCE_CAP_ON_BOOT", "1") == "1":
            _egc(app)
    except Exception as _e:
        try:
            app.logger.warning(f"enforce_cap_on_boot: {_e}")
        except Exception:
            pass
"""
    if "enforce_cap_on_boot" not in code[start:insert_at]:
        code = code[:insert_at] + payload + code[insert_at:]

Path("backend/__init__.py").write_text(code)
print("✓ __init__.py listo (migrate_min+índices y boot-cap)")
PY

# ---- 3) routes.py: intentar inyectar cap en GET/POST /notes (si existen) ----
backup backend/routes.py
python - <<'PY'
from pathlib import Path, re
p = Path("backend/routes.py")
code = p.read_text()

# Asegurar import current_app si vamos a llamar cap dentro de view
if "from flask import" in code and "current_app" not in code:
    code = code.replace("from flask import", "from flask import current_app, ")

# Helper para insertar dentro del cuerpo de una función después de la línea 'def ...:'
def inject_in_func(deco_pat, snippet):
    global code
    m = re.search(deco_pat, code, re.S|re.M)
    if not m: 
        return False
    # Ubicar 'def ...:' que sigue a los decoradores
    dm = re.search(r"\n\s*def\s+\w+\s*\([^)]*\)\s*:\s*", code[m.end():])
    if not dm:
        return False
    def_start = m.end() + dm.start()
    def_end   = m.end() + dm.end()
    # Detectar indent (espacios) de la función
    line = re.search(r"\n(\s*)def\s+\w+\s*\(", code[def_start-100:def_start+50])
    indent = line.group(1) if line else "    "
    insertion = "\n" + indent + snippet.replace("\n", "\n"+indent) + "\n"
    # Evitar duplicado
    if snippet.strip() in code[def_end:def_end+300]:
        return True
    code = code[:def_end] + insertion + code[def_end:]
    return True

snippet = """# enforce cap (ligero; no bloquea si falla)
try:
    from .tasks import enforce_global_cap as _egc
    _egc(current_app)
except Exception:
    pass"""

found_any = False

# POST /notes (soporta @bp.post o @bp.route con methods incluyendo POST, y decoradores encima)
pat_post = r"@bp\.(?:post|route)\(\s*[\"']\/notes[\"'](?:\s*,\s*methods\s*=\s*\[[^\]]*POST[^\]]*\])?\s*\)\s*(?:\n\s*@[^\n]+)*"
found_any = inject_in_func(pat_post, snippet) or found_any

# GET /notes
pat_get = r"@bp\.(?:get|route)\(\s*[\"']\/notes[\"'](?:\s*,\s*methods\s*=\s*\[[^\]]*GET[^\]]*\])?\s*\)\s*(?:\n\s*@[^\n]+)*"
found_any = inject_in_func(pat_get, snippet) or found_any

Path("backend/routes.py").write_text(code)
print("✓ routes.py: inyección GET/POST:", "OK" if found_any else "no encontrada (no crítico)")
PY

# ---- 4) Validación sintaxis, commit y push ----
python -m py_compile backend/tasks.py backend/__init__.py backend/routes.py

git add backend/tasks.py backend/__init__.py backend/routes.py
git commit -m "feat(cap): función enforce_global_cap()+boot hook+purge hook; inyección opcional en GET/POST /notes; índices en note" || true
git push -u origin "$(git rev-parse --abbrev-ref HEAD)"

echo
echo "✅ Sugerido: en Render → Environment:"
echo "   MAX_NOTES=20000      (Starter; con 2GB RAM podés subir a 50000)"
echo "   ENFORCE_CAP_ON_BOOT=1"
echo "Luego redeploy y probá /api/notes?page=1"
