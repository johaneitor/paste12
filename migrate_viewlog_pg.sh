#!/usr/bin/env bash
set -Eeuo pipefail

python - <<'PY'
import os, sys
from sqlalchemy import create_engine, text

url = os.getenv('DATABASE_URL') or os.getenv('SQLALCHEMY_DATABASE_URI')
if not url:
    print("❌ No DATABASE_URL/SQLALCHEMY_DATABASE_URI en el entorno.")
    sys.exit(1)

eng = create_engine(url, pool_pre_ping=True)
dialect = eng.dialect.name
print(f"Conectando a {dialect}…")

with eng.begin() as conn:
    def col_exists(table, col):
        if dialect == 'postgresql':
            q = text("""
                SELECT 1 FROM information_schema.columns
                WHERE table_name=:t AND column_name=:c
            """)
            return bool(conn.execute(q, {"t": table, "c": col}).first())
        else:
            # SQLite y otros
            try:
                conn.execute(text(f"SELECT {col} FROM {table} LIMIT 0"))
                return True
            except Exception:
                return False

    # 1) Columna view_date
    if not col_exists("view_log", "view_date"):
        if dialect == 'postgresql':
            conn.execute(text("ALTER TABLE view_log ADD COLUMN view_date date"))
            conn.execute(text("UPDATE view_log SET view_date = (created_at AT TIME ZONE 'UTC')::date WHERE view_date IS NULL"))
            conn.execute(text("ALTER TABLE view_log ALTER COLUMN view_date SET NOT NULL"))
        else:
            # SQLite: añade columna (sin NOT NULL inicial), rellena, luego NOT NULL si versiones lo permiten
            conn.execute(text("ALTER TABLE view_log ADD COLUMN view_date DATE"))
            conn.execute(text("UPDATE view_log SET view_date = date(created_at) WHERE view_date IS NULL"))
        print("✓ view_date creada y poblada")

    # 2) Constraint único (nota + fingerprint + día)
    if dialect == 'postgresql':
        uq_old = conn.execute(text("""
            SELECT conname FROM pg_constraint
            WHERE conrelid = 'view_log'::regclass
              AND contype='u' AND conname = 'uq_view_note_fp'
        """)).first()
        if uq_old:
            conn.execute(text('ALTER TABLE view_log DROP CONSTRAINT "uq_view_note_fp"'))
            print("✓ UNIQUE antiguo uq_view_note_fp eliminado")

        uq_new = conn.execute(text("""
            SELECT conname FROM pg_constraint
            WHERE conrelid = 'view_log'::regclass
              AND contype='u' AND conname = 'uq_view_note_fp_day'
        """)).first()
        if not uq_new:
            conn.execute(text('ALTER TABLE view_log ADD CONSTRAINT "uq_view_note_fp_day" UNIQUE (note_id, fingerprint, view_date)'))
            print("✓ UNIQUE uq_view_note_fp_day creado")
    else:
        # SQLite: usa índice único
        conn.execute(text("CREATE UNIQUE INDEX IF NOT EXISTS uq_view_note_fp_day ON view_log(note_id, fingerprint, view_date)"))
        print("✓ UNIQUE index uq_view_note_fp_day (SQLite)")

    # 3) Índices útiles
    conn.execute(text("CREATE INDEX IF NOT EXISTS ix_view_log_note_id ON view_log (note_id)"))
    conn.execute(text("CREATE INDEX IF NOT EXISTS ix_view_log_view_date ON view_log (view_date)"))

print("✓ ViewLog migrado/asegurado.")
PY
