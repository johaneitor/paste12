#!/usr/bin/env bash
set -euo pipefail
echo "[+] Migrando esquema para eventos…"

python - <<'PY'
import os, re, sqlite3, sys

DBURL = os.environ.get("DATABASE_URL","").strip()
if DBURL and DBURL.startswith("postgres://"):
    DBURL = "postgresql://" + DBURL[len("postgres://"):]
USE_PG = DBURL.startswith("postgresql://")

if USE_PG:
    # Postgres
    import sqlalchemy as sa
    eng = sa.create_engine(DBURL, future=True)
    with eng.begin() as cx:
        cx.exec_driver_sql("""
        CREATE TABLE IF NOT EXISTS like_log (
          id SERIAL PRIMARY KEY,
          note_id INTEGER NOT NULL,
          actor_fp VARCHAR(64) NOT NULL,
          created_at TIMESTAMP NOT NULL DEFAULT NOW()
        );
        """)
        cx.exec_driver_sql("""
        CREATE TABLE IF NOT EXISTS view_log (
          id SERIAL PRIMARY KEY,
          note_id INTEGER NOT NULL,
          actor_fp VARCHAR(64) NOT NULL,
          seen_at TIMESTAMP NOT NULL DEFAULT NOW()
        );
        """)
        cx.exec_driver_sql("""
        CREATE UNIQUE INDEX IF NOT EXISTS ux_like_actor_note
          ON like_log(actor_fp, note_id);
        """)
        cx.exec_driver_sql("""
        CREATE INDEX IF NOT EXISTS ix_view_note_actor_time
          ON view_log(note_id, actor_fp, seen_at);
        """)
        # columnas en note (por si faltan)
        cx.exec_driver_sql("""ALTER TABLE note ADD COLUMN IF NOT EXISTS likes   INTEGER NOT NULL DEFAULT 0;""")
        cx.exec_driver_sql("""ALTER TABLE note ADD COLUMN IF NOT EXISTS views   INTEGER NOT NULL DEFAULT 0;""")
        cx.exec_driver_sql("""ALTER TABLE note ADD COLUMN IF NOT EXISTS reports INTEGER NOT NULL DEFAULT 0;""")
    print("[OK] Esquema en Postgres listo.")
else:
    # SQLite
    DB = os.environ.get("PASTE12_DB","app.db")
    cx = sqlite3.connect(DB)
    cx.execute("""
    CREATE TABLE IF NOT EXISTS like_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      note_id INTEGER NOT NULL,
      actor_fp TEXT NOT NULL,
      created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      UNIQUE(actor_fp, note_id)
    );
    """)
    cx.execute("""
    CREATE TABLE IF NOT EXISTS view_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      note_id INTEGER NOT NULL,
      actor_fp TEXT NOT NULL,
      seen_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
    );
    """)
    cx.execute("""CREATE INDEX IF NOT EXISTS ix_view_note_actor_time ON view_log(note_id, actor_fp, seen_at);""")
    # columnas en note (por si faltan)
    try: cx.execute("ALTER TABLE note ADD COLUMN likes INTEGER NOT NULL DEFAULT 0;")
    except Exception: pass
    try: cx.execute("ALTER TABLE note ADD COLUMN views INTEGER NOT NULL DEFAULT 0;")
    except Exception: pass
    try: cx.execute("ALTER TABLE note ADD COLUMN reports INTEGER NOT NULL DEFAULT 0;")
    except Exception: pass
    cx.commit(); cx.close()
    print("[OK] Esquema en SQLite listo.")
PY
