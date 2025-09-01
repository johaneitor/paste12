import os
# Asegura que patched_app resuelva la app correcta
os.environ.setdefault("APP_MODULE", "run:app")

# Bootstrap de DB solo en Postgres (idempotente)
try:
    from sqlalchemy import create_engine, text
    url = os.environ.get("DATABASE_URL", "")
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
except Exception as e:
    # No detenemos el arranque si falla el bootstrap; la app puede seguir
    print(f"[wsgiapp] Bootstrap DB omitido: {e}")

# Expone el WSGI final desde nuestro shim
from patched_app import app  # noqa: E402
