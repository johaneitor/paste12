#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(pwd)"
MODELS="${REPO_ROOT}/backend/models.py"
BACKEND_DIR="${REPO_ROOT}/backend"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
TMPDIR="${TMPDIR:-$PREFIX/tmp}"
LOG="${TMPDIR}/paste12_server.log"
SERVER="http://127.0.0.1:8000"

mkdir -p "$TMPDIR"
cp -f "$MODELS" "$MODELS.bak.$(date +%s)"

echo "➤ Reordenando imports en backend/models.py (los 'from __future__' al tope)"
python - <<'PY'
from pathlib import Path
p = Path("backend/models.py")
src = p.read_text(encoding="utf-8").splitlines()

# 1) Header (shebang/comentarios/encoding) y docstring superiores
i = 0
header = []
def is_header(l):
    s = l.strip()
    return s=="" or s.startswith("#") or s.startswith("#!") or s.startswith("# -*-")
while i < len(src) and is_header(src[i]):
    header.append(src[i]); i += 1

doc = []
if i < len(src) and src[i].lstrip().startswith(('"""',"'''")):
    q = src[i].lstrip()[:3]
    doc.append(src[i]); i += 1
    while i < len(src):
        doc.append(src[i])
        if src[i].strip().endswith(q):
            i += 1; break

body = src[i:]

# 2) Extraer TODOS los future imports del body
futures, rest = [], []
for ln in body:
    if ln.startswith("from __future__ import"):
        if ln not in futures:
            futures.append(ln)
    else:
        rest.append(ln)

# 3) Asegurar que 'from backend import db' exista y esté DESPUÉS de los futuros
has_db_import = any(l.strip()=="from backend import db" for l in rest)
if not has_db_import:
    rest.insert(0, "from backend import db")

# 4) Quitar cualquier 'from backend import db' antes de los futuros (por si quedó arriba)
#    Ya que reconstruimos, con esto aseguramos orden correcto.
rest = [l for l in rest if l.strip() != "from backend import db"]

# 5) Construir salida: header + doc + futures + línea en blanco + 'from backend import db' + resto
out = []
out.extend(header)
out.extend(doc)
out.extend(futures)
if futures: out.append("")
out.append("from backend import db")
out.extend(rest)

p.write_text("\n".join(out) + "\n", encoding="utf-8")
print("OK: models.py con futuros al tope y 'from backend import db' reubicado.")
PY

echo "➤ Matando procesos previos (run.py/waitress/flask)"
pkill -f "python .*run\.py" 2>/dev/null || true
pkill -f "waitress" 2>/dev/null || true
pkill -f "flask" 2>/dev/null || true
sleep 1

echo "➤ Limpiando __pycache__"
find "$BACKEND_DIR" -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true
find "$BACKEND_DIR" -name '*.pyc' -delete 2>/dev/null || true

echo "➤ create_all() dentro de app context"
python - <<'PY'
from run import app
from backend import db
with app.app_context():
    db.create_all()
print("create_all() OK")
PY

echo "➤ Levantando servidor (log: $LOG)"
nohup python "$REPO_ROOT/run.py" >"$LOG" 2>&1 & disown || true
sleep 2

http(){ curl -sS -m 8 -o /dev/null -w "%{http_code}" "$@"; }

echo "➤ Smoke GET /api/health → $(http ${SERVER}/api/health)"
echo "➤ Smoke GET /api/notes  → $(http ${SERVER}/api/notes)"
echo "➤ Smoke POST /api/notes → $(curl -sS -m 12 -H 'Content-Type: application/json' -d '{\"text\":\"nota tras models fix\",\"hours\":24}' -o /dev/null -w '%{http_code}' ${SERVER}/api/notes)"

echo "➤ Confirmar columnas mapeadas de Note"
python - <<'PY'
from run import app
from backend.models import Note
with app.app_context():
    print("Note mapped cols:", [c.name for c in Note.__table__.columns])
PY

echo "ℹ️ Si algo falla, ver log con: tail -n 200 \"$LOG\""
