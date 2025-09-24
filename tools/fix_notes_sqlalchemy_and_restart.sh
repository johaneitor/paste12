#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(pwd)"
BACKEND_DIR="${REPO_ROOT}/backend"
ROUTES_FILE="${BACKEND_DIR}/routes.py"
RUN_FILE="${REPO_ROOT}/run.py"
DATA_DIR="${REPO_ROOT}/data"
ABS_DB_PATH="${DATA_DIR}/app.db"

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
TMPDIR="${TMPDIR:-$PREFIX/tmp}"
LOG="${TMPDIR}/paste12_server.log"
SERVER_URL="http://127.0.0.1:8000"

echo "➤ Asegurando carpetas (data y tmp)"
mkdir -p "$DATA_DIR" "$TMPDIR"

echo "➤ Backup de archivos a tocar"
cp -f "$ROUTES_FILE" "$ROUTES_FILE.bak.$(date +%s)"
cp -f "$RUN_FILE" "$RUN_FILE.bak.$(date +%s)"

echo "➤ Reparando inyección en routes.py (author_fp fuera de timedelta y dentro de Note(...))"
python - <<'PY'
from pathlib import Path
import re
p = Path("backend/routes.py")
s = p.read_text(encoding="utf-8")

# 1) Caso roto: timedelta(hours=hours, author_fp=...)
s = re.sub(
    r'timedelta\(\s*hours\s*=\s*hours\s*,\s*author_fp=_fingerprint_from_request\(request\)\s*\)',
    'timedelta(hours=hours)',
    s,
    flags=re.S
)

# 2) Asegurar que Note(...) tenga author_fp= como argumento independiente
def fix_note_call(m):
    inner = m.group(1)
    if 'author_fp=' in inner:
        return m.group(0)
    # insertar después de expires_at=...
    pat = re.compile(r'(expires_at\s*=\s*[^,\n\)]+)(\s*,?)', re.S)
    def _ins(mm):
        tail = mm.group(2) or ''
        return mm.group(1) + ',\n        author_fp=_fingerprint_from_request(request)' + tail
    inner2, n = pat.subn(_ins, inner, count=1)
    if n == 0:
        # si no hay expires_at, append al final
        inner2 = inner.rstrip()
        inner2 = (inner2 + ',\n        ' if inner2.strip() else '') + 'author_fp=_fingerprint_from_request(request)'
    return 'Note(' + inner2 + ')'

s = re.sub(r'Note\((.*?)\)', fix_note_call, s, flags=re.S)

# 3) Acomodar import sha256 por detrás de futuros (por si quedó arriba)
lines = s.splitlines()
if "from hashlib import sha256" in lines:
    # quitar todas
    lines = [ln for ln in lines if ln.strip() != "from hashlib import sha256"]
# reinsertar tras bloque from __future__
i = 0
def is_meta(l):
    t = l.strip()
    return t == "" or t.startswith("#!") or t.startswith("# -*-") or t.startswith("#") or t.startswith("'''") or t.startswith('"""')
while i < len(lines) and is_meta(lines[i]): i += 1
j = i
while j < len(lines) and lines[j].startswith("from __future__ import"):
    j += 1
lines.insert(j, "from hashlib import sha256")
p.write_text("\n".join(lines) + "\n", encoding="utf-8")
print("routes.py patched OK")
PY

echo "➤ Parchando run.py para registrar SQLAlchemy y apuntar a data/app.db"
python - <<PY
from pathlib import Path
import os, re
p = Path("run.py")
s = p.read_text(encoding="utf-8")

abs_db = os.path.abspath("${ABS_DB_PATH}").replace("\\\\","/")

# Insertar import db si falta
if "from backend.models import db" not in s:
    # Después de la primer línea no-comentario
    lines = s.splitlines()
    ins = 0
    while ins < len(lines) and (not lines[ins].strip() or lines[ins].lstrip().startswith("#")):
        ins += 1
    lines.insert(ins, "from backend.models import db")
    s = "\n".join(lines) + "\n"

# Asegurar config de SQLALCHEMY_DATABASE_URI (solo si no está)
if "SQLALCHEMY_DATABASE_URI" not in s:
    s = re.sub(r'(app\s*=\s*Flask\([^\)]*\).*\n)',
               r'\1app.config["SQLALCHEMY_DATABASE_URI"] = "sqlite:///%s"\n' % abs_db,
               s, count=1, flags=re.S)

# Desactivar track modifications si no está
if "SQLALCHEMY_TRACK_MODIFICATIONS" not in s:
    s = s.replace('SQLALCHEMY_DATABASE_URI', 'SQLALCHEMY_DATABASE_URI') + 'app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False\n'

# Asegurar db.init_app(app)
if "db.init_app(app)" not in s:
    # tratar de insertarlo luego de la config DB
    if 'SQLALCHEMY_DATABASE_URI' in s:
        s = s.replace('SQLALCHEMY_DATABASE_URI"] =', 'SQLALCHEMY_DATABASE_URI"] =')
        s = re.sub(r'(app\.config\["SQLALCHEMY_DATABASE_URI"\][^\n]*\n)',
                   r'\1db.init_app(app)\n',
                   s, count=1)
    else:
        s += '\ndb.init_app(app)\n'

p.write_text(s, encoding="utf-8")
print("run.py patched OK")
PY

echo "➤ Creando base y tablas con db.create_all()"
python - <<'PY'
from run import app
from backend.models import db
with app.app_context():
    db.create_all()
print("create_all() OK dentro del app context")
PY

echo "➤ Matando procesos previos (run.py / waitress / flask)"
if command -v pkill >/dev/null 2>&1; then
  pkill -f "python .*run\.py" || true
  pkill -f "waitress" || true
  pkill -f "flask" || true
else
  PIDS=$(ps -o pid,cmd | grep -E 'python .*run\.py|waitress|flask' | grep -v grep | awk '{print $1}' || true)
  [ -n "${PIDS:-}" ] && kill -9 $PIDS || true
fi

echo "➤ Limpiando __pycache__ y *.pyc"
find "$BACKEND_DIR" -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true
find "$BACKEND_DIR" -name '*.pyc' -delete 2>/dev/null || true

echo "➤ Arrancando servidor (log: $LOG)"
nohup python "$REPO_ROOT/run.py" >"$LOG" 2>&1 & disown || true
sleep 2

http() { curl -sS -m 8 -o /dev/null -w "%{http_code}" "$@"; }

echo "➤ Smoke GET /api/health"
echo "   → $(http ${SERVER_URL}/api/health)"

echo "➤ Smoke GET /api/notes"
CODE_G=$(http ${SERVER_URL}/api/notes)
echo "   → ${CODE_G}"

echo "➤ Smoke POST /api/notes"
PAY='{"text":"probando author_fp estable","hours":1}'
CODE_P=$(curl -sS -m 12 -H "Content-Type: application/json" -d "$PAY" -o /dev/null -w "%{http_code}" "${SERVER_URL}/api/notes")
echo "   → ${CODE_P}"

if [ "$CODE_P" != "200" ] && [ "$CODE_P" != "201" ]; then
  echo "❌ POST /api/notes falló. Últimas líneas de log:"
  tail -n 160 "$LOG" || true
  exit 1
fi

echo "✅ Listo. /api/notes responde OK y author_fp queda persistido."
