#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# 0) Validación de DATABASE_URL
if [ -z "${DATABASE_URL:-}" ]; then
  echo "❌ Falta DATABASE_URL. Ejemplo:"
  echo "   export DATABASE_URL='postgres://usuario:pass@host:5432/dbname'"
  exit 1
fi

# 1) Parar servidor local (por si está usando SQLite)
pkill -f "python run.py" 2>/dev/null || true
pkill -f waitress 2>/dev/null || true
pkill -f gunicorn 2>/dev/null || true

# 2) Activar venv e instalar driver de Postgres
source venv/bin/activate
echo "📦 Instalando driver de Postgres (psycopg)…"
pip install -q "psycopg[binary]" || pip install -q psycopg2-binary

# 3) Crear el script de migración (SQLAlchemy 2.x)
cat > migrate_sqlite_to_pg.py <<'PY'
import os, sys
from datetime import datetime, timezone
from sqlalchemy import create_engine, text
from sqlalchemy.dialects.postgresql import insert as pg_insert

# --- Helpers ---------------------------------------------------------------
def normalize_pg_url(raw: str, driver: str) -> str:
    if raw.startswith("postgres://"):
        return raw.replace("postgres://", f"postgresql+{driver}://", 1)
    if raw.startswith("postgresql://") and "+psycopg" not in raw and "+psycopg2" not in raw:
        return raw.replace("postgresql://", f"postgresql+{driver}://", 1)
    return raw

def pick_driver() -> str:
    try:
        import psycopg  # v3
        return "psycopg"
    except Exception:
        try:
            import psycopg2  # v2
            return "psycopg2"
        except Exception:
            return "psycopg2"

def to_aware(dt):
    if dt is None:
        return None
    if isinstance(dt, datetime):
        return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)
    # intenta ISO, asume UTC si no trae tz
    try:
        d = datetime.fromisoformat(str(dt))
        return d if d.tzinfo else d.replace(tzinfo=timezone.utc)
    except Exception:
        return None

# --- CWD = raíz del proyecto ----------------------------------------------
root = os.getcwd()
sqlite_path = os.path.join(root, "instance", "production.db")
src_url = f"sqlite:///{sqlite_path}"

if not os.path.exists(sqlite_path):
    print(f"⚠️  No existe {sqlite_path}. Nada que migrar (¿ya estás usando Postgres?).")
    sys.exit(0)

raw_target = os.environ.get("DATABASE_URL", "")
if not raw_target:
    print("❌ DATABASE_URL no está definido.")
    sys.exit(1)

driver = pick_driver()
target_url = normalize_pg_url(raw_target, driver)

print(f"🔗 Origen (SQLite): {src_url}")
print(f"🔗 Destino (Postgres): {target_url}")

# --- Importar app/modelos para crear esquema destino -----------------------
os.environ["DISABLE_SCHEDULER"] = "1"  # evita scheduler en este proceso
from backend import create_app, db
from backend.models import Note
try:
    from backend.models import LikeLog
except Exception:
    LikeLog = None  # por si no existe aún

# Reconfiguramos el app para apuntar a Postgres al crear tablas
os.environ["DATABASE_URL"] = target_url
app = create_app()

from sqlalchemy import inspect

def table_exists_sqlite(conn, name:str)->bool:
    res = conn.exec_driver_sql("SELECT name FROM sqlite_master WHERE type='table' AND name=:t", {"t": name}).fetchone()
    return bool(res)

def sqlite_columns(conn, table:str):
    rows = conn.exec_driver_sql(f"PRAGMA table_info({table})").fetchall()
    return [r[1] for r in rows]  # second col is name

with app.app_context():
    # Crea tablas en destino (Postgres)
    db.create_all()

    # Engines
    src_engine = create_engine(src_url, future=True)
    tgt_engine = db.engine

    total_notes = total_ll = 0
    inserted_notes = inserted_ll = 0

    with src_engine.connect() as sconn, tgt_engine.begin() as tconn:
        # --- NOTAS ----------------------------------------------------------
        if table_exists_sqlite(sconn, "note"):
            scols = sqlite_columns(sconn, "note")
            prefer = ["id","text","timestamp","expires_at","reports","user_token","likes","views","reported_by"]
            cols = [c for c in prefer if c in scols]
            sel = f"SELECT {', '.join(cols)} FROM note ORDER BY id"
            rows = sconn.exec_driver_sql(sel).fetchall()
            total_notes = len(rows)

            batch = []
            for r in rows:
                rec = dict(zip(cols, r))
                if "timestamp" in rec:  rec["timestamp"]  = to_aware(rec["timestamp"])
                if "expires_at" in rec: rec["expires_at"] = to_aware(rec["expires_at"])
                batch.append(rec)
                if len(batch) >= 1000:
                    stmt = pg_insert(Note.__table__).values(batch).on_conflict_do_nothing(index_elements=["id"])
                    tconn.execute(stmt); batch.clear()
            if batch:
                stmt = pg_insert(Note.__table__).values(batch).on_conflict_do_nothing(index_elements=["id"])
                tconn.execute(stmt); inserted_notes += len(batch)
            # contar destino
            cnt = tconn.execute(text("SELECT COUNT(*) FROM note")).scalar() or 0
            inserted_notes = cnt

        # --- LIKE LOG -------------------------------------------------------
        if LikeLog and table_exists_sqlite(sconn, "like_log"):
            scols = sqlite_columns(sconn, "like_log")
            prefer = ["id","note_id","fingerprint","created_at"]
            cols = [c for c in prefer if c in scols]
            sel = f"SELECT {', '.join(cols)} FROM like_log ORDER BY id"
            rows = sconn.exec_driver_sql(sel).fetchall()
            total_ll = len(rows)

            batch = []
            for r in rows:
                rec = dict(zip(cols, r))
                if "created_at" in rec: rec["created_at"] = to_aware(rec["created_at"])
                batch.append(rec)
                if len(batch) >= 1000:
                    stmt = pg_insert(LikeLog.__table__).values(batch).on_conflict_do_nothing(constraint="uq_like_note_fp")
                    tconn.execute(stmt); batch.clear()
            if batch:
                stmt = pg_insert(LikeLog.__table__).values(batch).on_conflict_do_nothing(constraint="uq_like_note_fp")
                tconn.execute(stmt)
            # contar destino
            cnt = tconn.execute(text("SELECT COUNT(*) FROM like_log")).scalar() or 0
            inserted_ll = cnt

    print(f"✓ Migración terminada")
    print(f"  Notas: {total_notes} origen  → {inserted_notes} destino")
    if LikeLog:
        print(f"  Likes: {total_ll} origen  → {inserted_ll} destino")
PY

# 4) Ejecutar migración
echo "🚚 Migrando datos SQLite → Postgres…"
env DISABLE_SCHEDULER=1 python migrate_sqlite_to_pg.py
