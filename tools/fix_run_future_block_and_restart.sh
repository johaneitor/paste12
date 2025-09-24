#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(pwd)"
RUN_FILE="${REPO_ROOT}/run.py"
BACKEND_DIR="${REPO_ROOT}/backend"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
TMPDIR="${TMPDIR:-$PREFIX/tmp}"
LOG="${TMPDIR}/paste12_server.log"
SERVER_URL="http://127.0.0.1:8000"

echo "➤ Asegurando tmp: $TMPDIR"
mkdir -p "$TMPDIR"

echo "➤ Reordenando 'from __future__ import ...' al tope de run.py"
python - <<'PY'
from pathlib import Path
p = Path("run.py")
lines = p.read_text(encoding="utf-8").splitlines()

# 1) Capturar shebang/encoding/comentarios iniciales
idx = 0
header = []
while idx < len(lines) and (lines[idx].strip()=="" or lines[idx].lstrip().startswith("#")):
    header.append(lines[idx]); idx += 1

# 2) Capturar docstring de módulo si está al tope
doc = []
if idx < len(lines) and (lines[idx].lstrip().startswith('"""') or lines[idx].lstrip().startswith("'''")):
    q = lines[idx].lstrip()[:3]
    doc.append(lines[idx]); idx += 1
    while idx < len(lines):
        doc.append(lines[idx])
        if lines[idx].strip().endswith(q):
            idx += 1
            break
        idx += 1

# 3) Extraer TODOS los future imports en el resto del archivo
future, body = [], []
for ln in lines[idx:]:
    if ln.startswith("from __future__ import"):
        if ln not in future:
            future.append(ln)
    else:
        body.append(ln)

# 4) Ensamblar: header + docstring + future + body
out = []
out.extend(header)
out.extend(doc)
out.extend(future)
if future and (not out or out[-1]!=""):
    out.append("")  # línea en blanco
out.extend(body)

p.write_text("\n".join(out) + "\n", encoding="utf-8")
print("OK: future imports movidos al tope (tras docstring si existe).")
PY

echo "➤ Matando procesos previos (run.py/waitress/flask)"
pkill -f "python .*run\.py" 2>/dev/null || true
pkill -f "waitress" 2>/dev/null || true
pkill -f "flask" 2>/dev/null || true

echo "➤ Limpiando __pycache__"
find "$BACKEND_DIR" -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true
find "$BACKEND_DIR" -name '*.pyc' -delete 2>/dev/null || true

echo "➤ create_all() dentro de app context"
python - <<'PY'
from run import app
# Importa el db que usa la app (debes tenerlo en backend.models)
from backend.models import db
with app.app_context():
    db.create_all()
print("create_all() OK")
PY

echo "➤ Levantando servidor (log: $LOG)"
nohup python "$RUN_FILE" >"$LOG" 2>&1 & disown || true
sleep 2

http() { curl -sS -m 8 -o /dev/null -w "%{http_code}" "$@"; }

echo "➤ Smoke GET /api/health → $(http ${SERVER_URL}/api/health)"
echo "➤ Smoke GET /api/notes  → $(http ${SERVER_URL}/api/notes)"
echo "➤ Smoke POST /api/notes → $(curl -sS -m 12 -H 'Content-Type: application/json' -d '{\"text\":\"nota ok\",\"hours\":1}' -o /dev/null -w '%{http_code}' ${SERVER_URL}/api/notes)"

echo "ℹ️ Si algo falla, inspecciona el log:"
echo "  tail -n 120 \"$LOG\""
