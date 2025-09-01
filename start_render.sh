#!/usr/bin/env bash
set -euo pipefail

export APP_MODULE="${APP_MODULE:-run:app}"
export PORT="${PORT:-8000}"

# Bootstrap de DB (solo si es Postgres en Render)
python - <<'PY'
import os
from sqlalchemy import create_engine, text
url = os.environ.get("DATABASE_URL","")
if url.startswith("postgres"):
    eng = create_engine(url, pool_pre_ping=True)
    with eng.begin() as cx:
        cx.execute(text("""
            CREATE TABLE IF NOT EXISTS note(
                id SERIAL PRIMARY KEY,
                title TEXT,
                url TEXT,
                summary TEXT,
                content TEXT,
                timestamp TIMESTAMPTZ DEFAULT NOW(),
                likes INT DEFAULT 0,
                views INT DEFAULT 0,
                reports INT DEFAULT 0,
                author_fp VARCHAR(64)
            )
        """))
        cx.execute(text("ALTER TABLE note ADD COLUMN IF NOT EXISTS author_fp VARCHAR(64)"))
        cx.execute(text("CREATE INDEX IF NOT EXISTS idx_note_timestamp ON note (timestamp DESC, id DESC)"))
        cx.execute(text("CREATE INDEX IF NOT EXISTS idx_note_likes ON note (likes)"))
        cx.execute(text("CREATE INDEX IF NOT EXISTS idx_note_views ON note (views)"))
        cx.execute(text("CREATE INDEX IF NOT EXISTS idx_note_reports ON note (reports)"))
PY

# Lanzar Waitress sobre el shim patched_app (sin gunicorn)
python - <<'PY'
from waitress import serve
import os
import patched_app as pa
serve(pa.app, host="0.0.0.0", port=int(os.environ.get("PORT","8000")))
PY
