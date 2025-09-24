#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"

echo "[+] Patch: backend/modules/interactions.py (FK dinámica a Note.__tablename__)"
python - "$ROOT" <<'PY'
import re, sys, pathlib
p = pathlib.Path("backend/modules/interactions.py")
s = p.read_text(encoding="utf-8")

# 1) Asegurar constante NOTE_TABLE y uso en la FK
if "NOTE_TABLE =" not in s:
    # Inserta tras la definición (o import) de Note/db
    s = s.replace(
        "db = None\nNote = None",
        "db = None\nNote = None\n"
    )
    s = s.replace(
        "    db, Note = _db, _Note",
        "    db, Note = _db, _Note"
    )
    # Inserta NOTE_TABLE pegado tras Note/db resueltos
    s = re.sub(
        r"(\bNote\s*=\s*_Note\b.*?\n)",
        r"\1NOTE_TABLE = getattr(Note, \"__tablename__\", \"note\")\n",
        s, count=1, flags=re.S
    )

    # En fallback también
    if "class Note(db.Model):" in s and "NOTE_TABLE = getattr(Note," not in s:
        s = s.replace(
            "class Note(db.Model):",
            "class Note(db.Model):"
        )
        s += "\nNOTE_TABLE = getattr(Note, \"__tablename__\", \"note\")\n"

# 2) Reemplazar FK hardcodeada "note.id" por f"{NOTE_TABLE}.id"
s = re.sub(
    r'ForeignKey\(\s*["\']note\.id["\']',
    'ForeignKey(f"{NOTE_TABLE}.id"',
    s
)

# 3) Exportar helper para (re)crear tabla y reparar FK
if "def repair_interaction_table(" not in s:
    s += r"""

# === helpers de mantenimiento (drop&create seguro) ===
def create_interaction_table(bind=None):
    try:
        InteractionEvent.__table__.create(bind=bind or db.engine, checkfirst=True)
        return True
    except Exception:
        return False

def drop_interaction_table(bind=None):
    try:
        InteractionEvent.__table__.drop(bind=bind or db.engine, checkfirst=True)
        return True
    except Exception:
        return False

def fk_points_to_correct_note(inspector) -> bool:
    try:
        fks = inspector.get_foreign_keys("interaction_event")
        for fk in fks:
            if fk.get("referred_table") == NOTE_TABLE:
                return True
        return False
    except Exception:
        return False

def repair_interaction_table():
    from sqlalchemy import inspect
    insp = inspect(db.engine)
    tables = set(insp.get_table_names())
    if "interaction_event" not in tables:
        # no existe: crear
        return create_interaction_table()
    # existe: validar FK
    if fk_points_to_correct_note(insp):
        return True  # ya está bien
    # mal apuntada: dropear y recrear
    ok = drop_interaction_table()
    if not ok:
        return False
    return create_interaction_table()
"""
p.write_text(s, encoding="utf-8")
print("[OK] interactions.py actualizado")
PY

echo "[+] Patch: render_entry.py (endpoint /api/notes/repair-interactions)"
python - <<'PY'
import re, sys, pathlib
p = pathlib.Path("render_entry.py")
s = p.read_text(encoding="utf-8")

# Garantizar imports
if "from backend.modules.interactions import" not in s:
    s = "from backend.modules.interactions import repair_interaction_table, ensure_schema, register_alias_into\n" + s
else:
    if "repair_interaction_table" not in s:
        s = s.replace(
            "from backend.modules.interactions import",
            "from backend.modules.interactions import repair_interaction_table,",
        )

# Endpoint mantenimiento
if "endpoint=\"repair_interaction_schema\"" not in s:
    s += r"""

# === mantenimiento: POST /api/notes/repair-interactions ===
try:
    from flask import Blueprint, jsonify
    _mnt2 = Blueprint("interactions_repair", __name__)

    @_mnt2.post("/notes/repair-interactions", endpoint="repair_interaction_schema")
    def _repair_interactions():
        try:
            ok = repair_interaction_table()
            return jsonify(ok=bool(ok)), (200 if ok else 500)
        except Exception as e:
            return jsonify(ok=False, error="repair_failed", detail=str(e)), 500

    try:
        app.register_blueprint(_mnt2, url_prefix="/api")
    except Exception:
        pass
except Exception:
    pass
"""
p.write_text(s, encoding="utf-8")
print("[OK] render_entry.py actualizado")
PY

echo "[+] Commit & push"
git add -A
git commit -m "fix(interactions): FK dynamic to Note.__tablename__; add repair endpoint to recreate interaction_event" || true
git push -u --force-with-lease origin "$(git rev-parse --abbrev-ref HEAD)"

cat <<'NEXT'

[•] Hecho. Ahora:

APP="https://paste12-rmsk.onrender.com"

# 1) Reparar (drop & create si era incorrecta la FK):
curl -si -X POST "$APP/api/notes/repair-interactions" | sed -n '1,120p'

# 2) Verificar diagnósticos (ya no deben fallar):
curl -s "$APP/api/notes/diag" | jq .

# 3) Probar con un ID válido:
ID=$(curl -s "$APP/api/notes?page=1" | jq -r '.[0].id'); echo "Usando ID=$ID"
curl -si -X POST "$APP/api/ix/notes/$ID/like"  | sed -n '1,120p'
curl -si -X POST "$APP/api/ix/notes/$ID/view"  | sed -n '1,120p'
curl -si      "$APP/api/ix/notes/$ID/stats"   | sed -n '1,160p'

# NOTA: ejecuta cada curl en su propia línea (o usa &&). 
# Los errores de sed que viste fueron por mezclar varios 'curl | sed' en una sola línea.
NEXT
