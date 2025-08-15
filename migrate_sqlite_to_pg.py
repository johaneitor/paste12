import os
from sqlalchemy import create_engine, text
from sqlalchemy.exc import SQLAlchemyError

SQLITE = os.environ.get("SQLITE_URL", "sqlite:///instance/production.db")
PG     = os.environ.get("DATABASE_URL")
if not PG:
    raise SystemExit("❌ Falta DATABASE_URL (PostgreSQL).")

print("Origen (SQLite):", SQLITE)
print("Destino (Postgres):", PG.split('@')[-1])

src = create_engine(SQLITE, future=True)
dst = create_engine(PG, future=True)

with dst.begin() as conn:
    conn.execute(text("""
    CREATE TABLE IF NOT EXISTS note(
      id SERIAL PRIMARY KEY,
      text VARCHAR(500) NOT NULL,
      timestamp TIMESTAMPTZ,
      expires_at TIMESTAMPTZ,
      reports INTEGER DEFAULT 0,
      user_token VARCHAR(64),
      likes INTEGER DEFAULT 0,
      views INTEGER DEFAULT 0
    )
    """))
    print("✓ Tabla note en Postgres OK")

rows = []
with src.connect() as s:
    rows = s.execute(text("SELECT id,text,timestamp,expires_at,reports,user_token,likes,views FROM note")).all()
print(f"Encontradas {len(rows)} filas en SQLite")

ins = text("""
INSERT INTO note (id, text, timestamp, expires_at, reports, user_token, likes, views)
VALUES (:id, :text, :ts, :exp, :rep, :tok, :lik, :vi)
ON CONFLICT (id) DO NOTHING
""")

batch = 0
with dst.begin() as d:
    for r in rows:
        d.execute(ins, dict(
            id=r.id, text=r.text, ts=r.timestamp, exp=r.expires_at,
            rep=r.reports, tok=r.user_token, lik=r.likes or 0, vi=r.views or 0
        ))
        batch += 1
print(f"✓ Migradas {batch} filas a Postgres")
