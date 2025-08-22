#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(pwd)"
DATA_DIR="${REPO_ROOT}/data"
DB_PATH="${DATA_DIR}/app.db"
BACKEND_DIR="${REPO_ROOT}/backend"
INIT_FILE="${BACKEND_DIR}/__init__.py"
MODELS_FILE="${BACKEND_DIR}/models.py"
ROUTES_FILE="${BACKEND_DIR}/routes.py"
RUN_FILE="${REPO_ROOT}/run.py"

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
TMPDIR="${TMPDIR:-$PREFIX/tmp}"
LOG="${TMPDIR}/paste12_server.log"
SERVER_URL="http://127.0.0.1:8000"

echo "➤ Preparando carpetas (data/tmp)"
mkdir -p "$DATA_DIR" "$TMPDIR"

echo "➤ Backups de archivos clave"
cp -f "$INIT_FILE"   "$INIT_FILE.bak.$(date +%s)"   2>/dev/null || true
cp -f "$MODELS_FILE" "$MODELS_FILE.bak.$(date +%s)" 2>/dev/null || true
cp -f "$ROUTES_FILE" "$ROUTES_FILE.bak.$(date +%s)" 2>/dev/null || true
cp -f "$RUN_FILE"    "$RUN_FILE.bak.$(date +%s)"    2>/dev/null || true

# ─────────────────────────────────────────────────────────
# 1) backend/__init__.py → UNA SOLA instancia de SQLAlchemy
# ─────────────────────────────────────────────────────────
python - <<'PY'
from pathlib import Path
import re
p = Path("backend/__init__.py")
s = p.read_text(encoding="utf-8")

# Asegurar import correcto
if "from flask_sqlalchemy import SQLAlchemy" not in s:
    s = "from flask_sqlalchemy import SQLAlchemy\n" + s

# Quitar definiciones duplicadas de db = SQLAlchemy()
lines = s.splitlines()
new = []
db_set = False
for ln in lines:
    if re.search(r'\bdb\s*=\s*SQLAlchemy\s*\(\s*\)', ln):
        if not db_set:
            new.append("db = SQLAlchemy()")
            db_set = True
        else:
            # saltar duplicados
            continue
    else:
        new.append(ln)
p.write_text("\n".join(new) + "\n", encoding="utf-8")
print("INIT: unificada instancia db = SQLAlchemy()")
PY

# ─────────────────────────────────────────────────────────
# 2) backend/models.py → usar from backend import db, y asegurar author_fp
# ─────────────────────────────────────────────────────────
python - <<'PY'
from pathlib import Path
import re
pm = Path("backend/models.py")
s = pm.read_text(encoding="utf-8")

# 2.1 Usar el db compartido
# eliminar creaciones locales de SQLAlchemy()
s = re.sub(r'from\s+flask_sqlalchemy\s+import\s+SQLAlchemy.*', '', s)
s = re.sub(r'\bdb\s*=\s*SQLAlchemy\s*\(\s*\)\s*', '', s)

# asegurar import 'from backend import db'
if "from backend import db" not in s:
    s = "from backend import db\n" + s

# asegurar imports comunes
if "from datetime import datetime" not in s:
    s = "from datetime import datetime\n" + s
if "from sqlalchemy" in s and "String" not in s:
    s = re.sub(r'(from sqlalchemy .*import [^\n]*)', r'\1, String', s)
elif "from sqlalchemy" not in s:
    s = "from sqlalchemy import String, Index\n" + s
elif "Index" not in s:
    s = re.sub(r'(from sqlalchemy .*import [^\n]*)', r'\1, Index', s)

# 2.2 Asegurar que la clase Note tenga author_fp
def ensure_author_fp(src):
    # Buscar clase Note (sin asumir base exacta)
    m = re.search(r'class\s+Note\s*\((.*?)\):', src)
    if not m:
        return src
    body_start = m.end()
    # encontrar el bloque de la clase (hasta una línea que no esté indentada o fin)
    lines = src.splitlines(keepends=True)
    # calcular índice de línea donde empieza el body
    prefix = src[:body_start]
    head_lines = prefix.splitlines(keepends=True)
    i = len(head_lines)
    # recorrer el body para detectar si ya está author_fp
    has = False
    for j in range(i, len(lines)):
        if lines[j].startswith(("class ", "@")):  # fin de clase por heurística
            break
        if 'author_fp' in lines[j]:
            has = True
            break
    if has:
        return src
    # Insertar author_fp antes del siguiente atributo o al final del bloque
    inserted = False
    for j in range(i, len(lines)):
        # si encontramos una línea no indentada -> fin de clase
        if not lines[j].startswith((" ", "\t")):
            insert_at = j
            break
    else:
        insert_at = len(lines)

    # línea de columna (usa db.Column para Flask-SQLAlchemy)
    col = "    author_fp = db.Column(db.String(128), nullable=True, index=True)\n"
    lines.insert(insert_at, col)
    return "".join(lines)

s2 = ensure_author_fp(s)

pm.write_text(s2, encoding="utf-8")
print("MODELS: usando backend.db y Note.author_fp asegurado")
PY

# ─────────────────────────────────────────────────────────
# 3) routes.py → asegurar import de Note desde backend.models (una sola)
# ─────────────────────────────────────────────────────────
python - <<'PY'
from pathlib import Path
import re
pr = Path("backend/routes.py")
s = pr.read_text(encoding="utf-8")

# Quitar imports alternativos de Note
s = re.sub(r'from\s+.*\s+import\s+Note\s*', '', s)
# Asegurar import correcto
s = "from backend.models import Note\n" + s if "from backend.models import Note" not in s else s

# (ya tenemos helper fingerprint de pasos previos)

pr.write_text(s, encoding="utf-8")
print("ROUTES: import Note unificado desde backend.models")
PY

# ─────────────────────────────────────────────────────────
# 4) run.py → importar db desde backend, registrar y configurar URI
# ─────────────────────────────────────────────────────────
python - <<'PY'
from pathlib import Path
import os, re
p = Path("run.py")
s = p.read_text(encoding="utf-8")
abs_db = os.path.abspath("data/app.db").replace("\\\\","/")

# mover future imports arriba se hizo antes, mantenemos
# asegurar 'from backend import db' y NO 'from backend.models import db'
s = re.sub(r'from\s+backend\.models\s+import\s+db', '', s)
if "from backend import db" not in s:
    # insertar tras bloque de futuros
    lines = s.splitlines()
    i = 0
    while i < len(lines) and (lines[i].strip()=="" or lines[i].lstrip().startswith("#") or
                              lines[i].lstrip().startswith('"""') or lines[i].lstrip().startswith("'''") ):
        i += 1
    while i < len(lines) and lines[i].startswith("from __future__ import"):
        i += 1
    lines.insert(i, "from backend import db")
    s = "\n".join(lines)

# asegurar SQLALCHEMY_DATABASE_URI
if "SQLALCHEMY_DATABASE_URI" not in s:
    s = re.sub(r'(app\s*=\s*Flask\([^\)]*\).*\n)', r'\1app.config["SQLALCHEMY_DATABASE_URI"] = "sqlite:///%s"\n' % abs_db, s, count=1, flags=re.S)
# track_modifications off
if "SQLALCHEMY_TRACK_MODIFICATIONS" not in s:
    s += '\napp.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False\n'
# init_app
if "db.init_app(app)" not in s:
    s += '\ndb.init_app(app)\n'

p.write_text(s, encoding="utf-8")
print("RUN: usa backend.db, URI sqlite:///data/app.db, init_app listo")
PY

# ─────────────────────────────────────────────────────────
# 5) Migración DB: añadir columna e índice si falta (tabla ya creada)
# ─────────────────────────────────────────────────────────
python - <<'PY'
import sqlite3, os
dbp = os.path.join("data","app.db")
os.makedirs("data", exist_ok=True)
con = sqlite3.connect(dbp)
cur = con.cursor()
# ¿existe notes?
cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='notes'")
if cur.fetchone():
    # ¿existe columna?
    cur.execute("PRAGMA table_info(notes)")
    cols = [r[1] for r in cur.fetchall()]
    if 'author_fp' not in cols:
        cur.execute("ALTER TABLE notes ADD COLUMN author_fp VARCHAR(128)")
        print("DB: columna author_fp agregada")
    # índice
    cur.execute("PRAGMA index_list(notes)")
    idx = [r[1] for r in cur.fetchall()]
    if 'ix_notes_author_fp' not in idx:
        cur.execute("CREATE INDEX IF NOT EXISTS ix_notes_author_fp ON notes(author_fp)")
        print("DB: índice ix_notes_author_fp creado")
con.commit(); con.close()
PY

# ─────────────────────────────────────────────────────────
# 6) kill, create_all, restart, smokes
# ─────────────────────────────────────────────────────────
echo "➤ Matando procesos previos (run.py / waitress / flask)"
pkill -f "python .*run\.py" 2>/dev/null || true
pkill -f "waitress" 2>/dev/null || true
pkill -f "flask" 2>/dev/null || true
sleep 1

echo "➤ Limpiando caches"
find "$BACKEND_DIR" -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true
find "$BACKEND_DIR" -name '*.pyc' -delete 2>/dev/null || true

echo "➤ create_all() dentro de app context"
python - <<'PY'
from run import app
from backend import db
with app.app_context():
    db.create_all()
print("create_all OK")
PY

echo "➤ Arrancando servidor (log: $LOG)"
nohup python "$REPO_ROOT/run.py" >"$LOG" 2>&1 & disown || true
sleep 2

http() { curl -sS -m 8 -o /dev/null -w "%{http_code}" "$@"; }

echo "➤ Smoke GET /api/health → $(http ${SERVER_URL}/api/health)"
echo "➤ Smoke GET /api/notes  → $(http ${SERVER_URL}/api/notes)"
echo "➤ Smoke POST /api/notes → $(curl -sS -m 12 -H 'Content-Type: application/json' -d '{\"text\":\"nota unificada\",\"hours\":24}' -o /dev/null -w '%{http_code}' ${SERVER_URL}/api/notes)"

echo "ℹ️ Si algo falla, ver log con:"
echo "   tail -n 160 \"$LOG\""
