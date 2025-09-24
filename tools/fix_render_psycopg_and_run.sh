#!/usr/bin/env bash
set -Eeuo pipefail

# 1) Ajustar requirements: relajar psycopg a un rango disponible en Render
if [ -f requirements.txt ]; then
  cp -f requirements.txt "requirements.txt.bak.$(date +%s)"
  # eliminar líneas previas de psycopg/psycopg2 por si acaso
  sed -i '/^psycopg\(\|\[binary\]\)/d' requirements.txt || true
else
  touch requirements.txt
fi
# agregar el pin estable (parches permitidos)
echo 'psycopg[binary]>=3.2.2,<3.3' >> requirements.txt

# asegurarnos de que gunicorn esté presente (por Procfile)
grep -q '^gunicorn' requirements.txt || echo 'gunicorn==22.0.0' >> requirements.txt
# asegurar mínimos necesarios (si faltaran)
grep -q '^Flask==' requirements.txt || echo 'Flask==3.0.3' >> requirements.txt
grep -q '^Flask-SQLAlchemy==' requirements.txt || echo 'Flask-SQLAlchemy==3.1.1' >> requirements.txt
grep -q '^SQLAlchemy==' requirements.txt || echo 'SQLAlchemy==2.0.31' >> requirements.txt
grep -q '^Werkzeug==' requirements.txt || echo 'Werkzeug==3.1.3' >> requirements.txt

# 2) Normalizar run.py para ambos esquemas: postgres:// y postgresql://
cp -f run.py "run.py.bak.$(date +%s)"
python - <<'PY'
from pathlib import Path
import re

p = Path("run.py")
s = p.read_text(encoding="utf-8")

# Reemplazar bloque _db_uri() si existe; si no, inyectarlo.
pat = r"def _db_uri\(\).*?\n\n"
new = (
"""def _db_uri() -> str:
    uri = os.getenv("DATABASE_URL")
    if uri:
        # postgres -> postgresql+psycopg
        uri = re.sub(r'^postgres://', 'postgresql+psycopg://', uri)
        # postgresql:// -> postgresql+psycopg:// si no trae driver
        if uri.startswith('postgresql://') and '+psycopg://' not in uri:
            uri = uri.replace('postgresql://', 'postgresql+psycopg://', 1)
        return uri
    # Fallback SQLite local
    db_path = pathlib.Path('data/app.db').resolve()
    return f"sqlite:///{db_path}\"\n\n"""
)

if "def _db_uri()" in s:
    s = re.sub(pat, new, s, flags=re.S)
else:
    # Insertar tras imports
    m = re.search(r"from backend import db\n", s)
    if m:
        idx = m.end()
        s = s[:idx] + "\nimport os, re, pathlib\n\n" + new + s[idx:]
    else:
        # si no encuentra el import esperado, no tocamos para no romper
        pass

p.write_text(s, encoding="utf-8")
print("run.py actualizado para normalizar DATABASE_URL.")
PY

# 3) Commit y push
git add requirements.txt run.py
git commit -m "fix(deploy): psycopg[binary]>=3.2.2,<3.3 y normalización de DATABASE_URL (postgres/postgresql)"
git push origin main || true

echo "Hecho. Volvé a lanzar el deploy en Render."
