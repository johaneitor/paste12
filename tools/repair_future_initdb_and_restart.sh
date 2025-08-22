#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(pwd)"
BACKEND_DIR="${REPO_ROOT}/backend"
ROUTES_FILE="${BACKEND_DIR}/routes.py"
DATA_DIR="${REPO_ROOT}/data"
DB_PATH="${DATA_DIR}/app.db"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
TMPDIR="${TMPDIR:-$PREFIX/tmp}"
LOG="${TMPDIR}/paste12_server.log"
SERVER_URL="http://127.0.0.1:8000"

echo "➤ Preparando tmp/logs en: $TMPDIR"
mkdir -p "$TMPDIR"
mkdir -p "$DATA_DIR"

# 1) Reordenar import: 'from hashlib import sha256' debe ir DESPUÉS de los 'from __future__ import ...'
echo "➤ Reparando encabezado de imports en routes.py (futuros primero)"
python - <<'PY'
from pathlib import Path
p = Path("backend/routes.py")
txt = p.read_text(encoding="utf-8").splitlines()
# quitar todas las líneas sha256 existentes
txt = [line for line in txt if line.strip() != "from hashlib import sha256"]
# encontrar bloque inicial de from __future__ import ...
i = 0
# saltar shebang/encoding/vacías/comentarios iniciales
def is_meta(l):
    s = l.strip()
    return (s == "" or s.startswith("#!") or s.startswith("# -*-") or s.startswith("#") or s.startswith("'''") or s.startswith('"""'))
while i < len(txt) and is_meta(txt[i]):
    i += 1
# si hay futuros, avanzar hasta el fin del bloque contiguo
j = i
while j < len(txt) and txt[j].startswith("from __future__ import"):
    j += 1
insert_pos = j  # justo después del bloque de futuros (o donde no haya)
txt.insert(insert_pos, "from hashlib import sha256")
Path("backend/routes.py").write_text("\n".join(txt) + "\n", encoding="utf-8")
print("OK: sha256 import reubicado tras futuros (pos:", insert_pos, ")")
PY

# 2) Crear tablas si faltan (incluye notes con author_fp)
echo "➤ Ejecutando Base.metadata.create_all()"
python - <<'PY'
from backend.models import Base, engine
print("DB usada:", engine.url)
Base.metadata.create_all(bind=engine)
print("create_all() OK")
PY

# 3) Matar procesos viejos y limpiar caches
echo "➤ Matando procesos previos (run.py / waitress / flask)"
if command -v pkill >/dev/null 2>&1; then
  pkill -f "python .*run.py" || true
  pkill -f "waitress" || true
  pkill -f "flask" || true
else
  PIDS=$(ps -o pid,cmd | grep -E 'python .*run\.py|waitress|flask' | grep -v grep | awk '{print $1}' || true)
  [ -n "${PIDS:-}" ] && kill -9 $PIDS || true
fi

echo "➤ Limpiando __pycache__ y *.pyc"
find "$BACKEND_DIR" -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true
find "$BACKEND_DIR" -name '*.pyc' -delete 2>/dev/null || true

# 4) Arrancar servidor
echo "➤ Arrancando servidor (logs en $LOG)"
nohup python "$REPO_ROOT/run.py" >"$LOG" 2>&1 & disown || true
sleep 2

# 5) Smokes
http() { curl -sS -m 7 -o /dev/null -w "%{http_code}" "$@"; }

echo "➤ Smoke GET /api/health"
echo "    → $(http "${SERVER_URL}/api/health")"
echo "➤ Smoke GET /api/notes"
CODE_G=$(http "${SERVER_URL}/api/notes")
echo "    → ${CODE_G}"
echo "➤ Smoke POST /api/notes"
PAY='{"text":"probando author_fp fix","hours":1}'
CODE_P=$(curl -sS -m 10 -H "Content-Type: application/json" -d "$PAY" -o /dev/null -w "%{http_code}" "${SERVER_URL}/api/notes")
echo "    → ${CODE_P}"

if [ "$CODE_P" != "200" ] && [ "$CODE_P" != "201" ]; then
  echo "❌ POST /api/notes no devolvió 200/201. Últimas líneas de log:"
  tail -n 120 "$LOG" || true
  exit 1
fi

echo "✅ Listo. Notas funcionando y author_fp persistente."
