#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

ROOT="$HOME/paste12"
cd "$ROOT"

ts=$(date +%s)

echo "🗂️  Backups con sufijo .$ts"

# ---------------------------------------------------------------------------
# 1) requirements.txt → añadir gunicorn y psycopg2-binary
# ---------------------------------------------------------------------------
cp -p requirements.txt requirements.txt.bak.$ts
touch requirements.txt
grep -q '^gunicorn' requirements.txt || echo 'gunicorn~=22.0' >> requirements.txt
grep -q '^psycopg2-binary' requirements.txt || echo 'psycopg2-binary~=2.9' >> requirements.txt
echo "✓ requirements.txt actualizado"

# ---------------------------------------------------------------------------
# 2) backend/__init__.py → usar DATABASE_URL si existe
# ---------------------------------------------------------------------------
cp -p backend/__init__.py backend/__init__.py.bak.$ts
python - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("backend/__init__.py")
s = p.read_text()

# Sustituir bloque de configuración para inyectar DATABASE_URL como preferente
pattern = r'app\.config\.from_mapping\([\s\S]*?\)'
repl = textwrap.dedent('''
app.config.from_mapping(
    SECRET_KEY=os.getenv("SECRET_KEY", "dev-secret"),
    SQLALCHEMY_DATABASE_URI=os.getenv(
        "DATABASE_URL",
        "sqlite:///" + os.path.join(app.instance_path, "production.db")
    ),
    SQLALCHEMY_TRACK_MODIFICATIONS=False,
    RATELIMIT_STORAGE_URL=os.getenv("RATELIMIT_STORAGE_URL", "memory://"),
    JSON_SORT_KEYS=False,
)
''').strip()

s = re.sub(pattern, repl, s, count=1)
Path("backend/__init__.py").write_text(s)
print("✓ backend/__init__.py configurado para PostgreSQL en Render (con fallback a SQLite)")
PY

# ---------------------------------------------------------------------------
# 3) render.yaml → servicio web + base de datos
# ---------------------------------------------------------------------------
cat > render.yaml <<'YAML'
services:
  - type: web
    name: paste12
    env: python
    plan: standard    # puedes empezar con 'starter' y subir luego
    buildCommand: pip install -r requirements.txt
    startCommand: gunicorn 'backend:create_app()' -w 4 -k gthread --threads 8 -b 0.0.0.0:$PORT
    autoDeploy: true
    envVars:
      - key: DATABASE_URL
        fromDatabase:
          name: paste12-db
          property: connectionString
      - key: SECRET_KEY
        generateValue: true
      # Descomenta si creas Redis en Render y quieres persistir rate limits
      # - key: RATELIMIT_STORAGE_URL
      #   value: redis://:PASSWORD@REDIS_HOST:6379/0

databases:
  - name: paste12-db
    plan: standard
YAML
echo "✓ render.yaml creado"

# ---------------------------------------------------------------------------
# 4) Script de migración: SQLite -> PostgreSQL
# ---------------------------------------------------------------------------
cat > migrate_sqlite_to_pg.py <<'PY'
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
PY
echo "✓ migrate_sqlite_to_pg.py creado"

# ---------------------------------------------------------------------------
# 5) .gitignore + init repo + commit
# ---------------------------------------------------------------------------
cat > .gitignore <<'GI'
venv/
__pycache__/
instance/
*.pyc
*.pyo
*.bak.*
*.arcade.bak.*
*.turq.bak.*
*.versus.bak.*
*.logoimg.bak.*
*.datauri.bak.*
GI

if [ ! -d .git ]; then
  git init
  git add .
  git commit -m "chore: preparar despliegue en Render (gunicorn, PG, render.yaml, migrador)"
  echo "✓ Repositorio git inicializado y primer commit hecho"
else
  git add .
  git commit -m "chore: preparar despliegue en Render (gunicorn, PG, render.yaml, migrador)" || true
  echo "✓ Cambios añadidos y commit actualizado"
fi

echo
echo "🚀  Listo para Render."
echo "Siguientes pasos:"
echo "1) Sube este repo a GitHub/GitLab:"
echo "     git branch -M main"
echo "     git remote add origin <URL de tu repo>"
echo "     git push -u origin main"
echo "2) En render.com → 'New +', elige tu repo, Render leerá render.yaml y creará:"
echo "   - Servicio web 'paste12'"
echo "   - Base de datos 'paste12-db' (PostgreSQL)"
echo "3) (Opcional) Migrar datos SQLite → Postgres DESDE TU ENTORNO LOCAL:"
echo "     source venv/bin/activate"
echo "     pip install -r requirements.txt"
echo "     SQLITE_URL=sqlite:///instance/production.db \\"
echo "     DATABASE_URL='postgresql://usuario:pass@host:5432/db' \\"
echo "       python migrate_sqlite_to_pg.py"
echo
echo "💡 Render usará: gunicorn 'backend:create_app()' -w 4 -k gthread --threads 8"
echo "   Ajusta workers/threads según métricas."
