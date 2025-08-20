#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
cd "$(dirname "$0")"
ts=$(date +%s)

# Backup
cp -p backend/__init__.py "backend/__init__.py.bak.$ts" 2>/dev/null || true

python - <<'PY'
from pathlib import Path
import re

p = Path("backend/__init__.py")
code = p.read_text(encoding="utf-8")

# Buscamos el primer "app = Flask(" y el primer "db = SQLAlchemy(" para insertar entre medio
m_app = re.search(r'^\s*app\s*=\s*Flask\([^)]*\)\s*$', code, re.M)
m_db  = re.search(r'^\s*db\s*=\s*SQLAlchemy\(', code, re.M)

if not m_app:
    raise SystemExit("❌ No encontré 'app = Flask(...)' en backend/__init__.py")
insert_at = m_app.end()

block = r"""
# --- DB robusto para Render (Postgres) ---
# Normaliza DATABASE_URL, agrega sslmode=require y ajusta el pool para evitar 'SSL SYSCALL EOF'
import os
db_url = os.getenv("DATABASE_URL")
if db_url:
    if db_url.startswith("postgres://"):
        db_url = "postgresql://" + db_url[len("postgres://"):]
    if db_url.startswith("postgresql://") and "sslmode=" not in db_url:
        sep = "&" if "?" in db_url else "?"
        db_url = db_url + f"{sep}sslmode=require"
    app.config["SQLALCHEMY_DATABASE_URI"] = db_url
else:
    # Fallback a SQLite en instance/
    os.makedirs(app.instance_path, exist_ok=True)
    app.config["SQLALCHEMY_DATABASE_URI"] = "sqlite:///" + os.path.join(app.instance_path, "production.db")

# Engine options (pool)
engine_opts = app.config.get("SQLALCHEMY_ENGINE_OPTIONS", {})
engine_opts.update({
    "pool_pre_ping": True,
    "pool_recycle": 300,  # segundos
    "pool_timeout": 30,
    "pool_size": 5,
    "max_overflow": 10,
})
app.config["SQLALCHEMY_ENGINE_OPTIONS"] = engine_opts
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
# --- fin parche DB ---
"""

# Evita insertar dos veces
if "pool_pre_ping" not in code and "sslmode=require" not in code:
    code = code[:insert_at] + block + code[insert_at:]
else:
    # Ya estaba configurado: solo asegúrate de sslmode=require si falta
    code = re.sub(
        r'(DATABASE_URL\"\)\))',
        r'\1  # (revisado por parche)',
        code
    )

p.write_text(code, encoding="utf-8")
print("✓ Parche DB insertado")
PY

# Prueba de compilación/import local
python -m compileall -q backend
python - <<'PY'
from backend import create_app
app = create_app()
print("✅ create_app() OK — listo para gunicorn")
PY

# Commit + push → redeploy
git add backend/__init__.py
git commit -m "fix(db): pool_pre_ping/pool_recycle y sslmode=require para Render Postgres (evitar EOF)" || true
git push -u origin "$(git rev-parse --abbrev-ref HEAD)"

echo "🚀 Subido. Cuando Render termine, entra con /?v=$(date +%s) para saltar caché del navegador."
