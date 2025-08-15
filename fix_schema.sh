#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

# 1) Parar servidor anterior (si hubiera)
pkill -f waitress 2>/dev/null || true

# 2) Activar venv y backup de la DB SQLite
source venv/bin/activate
DB="instance/production.db"
if [ -f "$DB" ]; then
  cp -p "$DB" "$DB.bak.$(date +%s)"
  echo "🗂️  Backup DB en $DB.bak.*"
else
  echo "ℹ️  Aún no existe $DB (se creará si hace falta)"
fi

# 3) Migración correcta con SQLAlchemy 2.x (exec_driver_sql)
python - <<'PY'
from backend import create_app, db
from sqlalchemy import text

NEEDED = {
    "likes": "INTEGER DEFAULT 0",
    "views": "INTEGER DEFAULT 0",
    "reported_by": "TEXT DEFAULT ''",
}

app = create_app()
with app.app_context():
    engine = db.engine
    with engine.connect() as conn:
        dialect = engine.dialect.name

        # Asegura que la tabla exista (si es primera vez)
        db.create_all()

        if dialect == "sqlite":
            # Lee columnas existentes
            cols = {row[1] for row in conn.exec_driver_sql("PRAGMA table_info(note)").fetchall()}
            for col, ddl in NEEDED.items():
                if col not in cols:
                    conn.exec_driver_sql(f"ALTER TABLE note ADD COLUMN {col} {ddl}")
                    print(f"✅ Añadida columna: {col} {ddl}")
                else:
                    print(f"= Columna ya existe: {col}")
        else:
            # Postgres u otro
            rows = conn.exec_driver_sql(
                "SELECT column_name FROM information_schema.columns WHERE table_name='note'"
            ).fetchall()
            cols = {r[0] for r in rows}
            for col, ddl in NEEDED.items():
                if col not in cols:
                    conn.exec_driver_sql(f"ALTER TABLE note ADD COLUMN {col} {ddl}")
                    print(f"✅ Añadida columna: {col} {ddl}")
                else:
                    print(f"= Columna ya existe: {col}")

print("✓ Migración completada: esquema consistente")
PY

# 4) Relanzar servidor
python run.py &
