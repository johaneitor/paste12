#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"

echo "[1/4] Migración de DB → índices únicos para idempotencia"
python - <<'PY'
import os, sqlite3, sys
url = os.environ.get("DATABASE_URL","sqlite:///app.db")
if url.startswith("sqlite:///"):
    db_path = url.replace("sqlite:///","")
    con = sqlite3.connect(db_path)
    cur = con.cursor()
    cur.execute("""CREATE TABLE IF NOT EXISTS interaction_event(
        id INTEGER PRIMARY KEY,
        note_id INTEGER NOT NULL,
        fp TEXT NOT NULL,
        type TEXT NOT NULL,
        bucket_15m INTEGER NOT NULL DEFAULT 0,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
    )""")
    # Índice único compuesto (like usa bucket_15m=0; view usa bucket de 15m)
    cur.execute("""CREATE UNIQUE INDEX IF NOT EXISTS uq_evt_note_fp_type_bucket
                   ON interaction_event(note_id, fp, type, bucket_15m)""")
    # Índices de apoyo
    cur.execute("""CREATE INDEX IF NOT EXISTS ix_evt_note_type_bucket
                   ON interaction_event(note_id, type, bucket_15m)""")
    con.commit(); con.close()
    print("[OK] SQLite migrado: índices creados")
else:
    # Postgres / otros → usar DDL portable
    import sqlalchemy as sa
    eng = sa.create_engine(url.replace("postgres://","postgresql://"))
    with eng.begin() as cx:
        cx.exec_driver_sql("""
        CREATE TABLE IF NOT EXISTS interaction_event(
          id SERIAL PRIMARY KEY,
          note_id INTEGER NOT NULL,
          fp VARCHAR(64) NOT NULL,
          type VARCHAR(16) NOT NULL,
          bucket_15m INTEGER NOT NULL DEFAULT 0,
          created_at TIMESTAMP NOT NULL DEFAULT NOW()
        );
        """)
        cx.exec_driver_sql("""
        DO $$
        BEGIN
          IF NOT EXISTS (
            SELECT 1 FROM pg_indexes WHERE indexname='uq_evt_note_fp_type_bucket'
          ) THEN
            CREATE UNIQUE INDEX uq_evt_note_fp_type_bucket
              ON interaction_event(note_id, fp, type, bucket_15m);
          END IF;
        END$$;
        """)
    print("[OK] DB migrada: índices creados")
PY

echo "[2/4] Inyectando rutas alias /api/ix/* (evitar choques con legacy)"
mkdir -p backend/modules
python - <<'PY'
import re, io, sys, pathlib
p = pathlib.Path("backend/modules/interactions.py")
s = p.read_text(encoding="utf-8")

# Asegurar que existe bp = Blueprint("interactions", __name__)
if "bp = Blueprint(" not in s:
    print("[!] No hallé Blueprint en interactions.py"); sys.exit(1)

# Agregar segundo blueprint alias si no existe
if "interactions_alias_bp" not in s:
    s += """

# --- Alias blueprint para evitar choques de rutas legacy ---
from flask import Blueprint as _BP
alias_bp = _BP("interactions_alias", __name__)

@alias_bp.post("/ix/notes/<int:note_id>/like")
def _alias_like(note_id:int):  # reusa la lógica
    return like_note(note_id)

@alias_bp.post("/ix/notes/<int:note_id>/view")
def _alias_view(note_id:int):
    return view_note(note_id)

@alias_bp.get("/ix/notes/<int:note_id>/stats")
def _alias_stats(note_id:int):
    return stats_note(note_id)

def register_alias_into(app):
    try:
        app.register_blueprint(alias_bp, url_prefix="/api")
    except Exception:
        pass
"""
# Extender register_into para registrar el alias también
if "def register_into(app):" in s and "register_alias_into(app)" not in s:
    s = re.sub(
        r"(def register_into\(app\):\n\s+#[^\n]*\n\s+try:\n\s+app\.register_blueprint\(bp, url_prefix=\"/api\"\)\n\s+except Exception:\n\s+    pass)",
        r"\1\n    # Alias /api/ix/*\n    try:\n        register_alias_into(app)\n    except Exception:\n        pass",
        s
    )

# Asegurar create_all sigue llamándose
if "ensure_schema()" not in s:
    s += "\nwith app.app_context():\n    ensure_schema()\n"

p.write_text(s, encoding="utf-8")
print("[OK] Alias /api/ix/* añadidos")
PY

echo "[3/4] Smoke E2E contra alias /api/ix/*"
PORT="${PORT:-8000}"
BASE="http://127.0.0.1:$PORT"
NEW=$(curl -s -X POST -H 'Content-Type: application/json' -d '{"text":"ix-hotfix","hours":24}' "$BASE/api/notes" || echo "")
NOTE_ID=$(echo "$NEW" | sed -n 's/.*"id":[[:space:]]*\([0-9]\+\).*/\1/p')
if [ -z "${NOTE_ID:-}" ]; then
  echo "    [!] No pude crear nota vía /api/notes; intentando seed dummy id=1"
  NOTE_ID=1
fi
echo "    NOTE_ID=$NOTE_ID"

echo "    → Like #1"
curl -s -i -X POST "$BASE/api/ix/notes/$NOTE_ID/like" | sed -n '1,40p'
echo "    → Like #2 (no debe subir)"
curl -s -i -X POST "$BASE/api/ix/notes/$NOTE_ID/like" | sed -n '1,40p'

echo "    → View #1"
curl -s -i -X POST "$BASE/api/ix/notes/$NOTE_ID/view" | sed -n '1,40p'
echo "    → View #2 (misma ventana)"
curl -s -i -X POST "$BASE/api/ix/notes/$NOTE_ID/view" | sed -n '1,40p'

echo "    → Stats"
curl -s -i "$BASE/api/ix/notes/$NOTE_ID/stats" | sed -n '1,80p'

echo "[4/4] (Opcional) Commit & push"
if [ "${AUTO_PUSH:-0}" = "1" ]; then
  git add -A
  git commit -m "hotfix(ix): unique index + alias /api/ix/* to avoid legacy collisions" || true
  git push -u --force-with-lease origin "$(git rev-parse --abbrev-ref HEAD)"
fi

echo
echo "[i] Cuando el front ya consuma /api/ix/* OK, limpiamos rutas legacy y movemos /ix → canónicas."
