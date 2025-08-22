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

echo "➤ Asegurando rutas"
mkdir -p "$TMPDIR" "$DATA_DIR"

echo "➤ Fix de imports en routes.py (poner sha256 después de from __future__)"
python - <<'PY'
from pathlib import Path
p = Path("backend/routes.py")
txt = p.read_text(encoding="utf-8").splitlines()
# quitar duplicados de sha256
txt = [l for l in txt if l.strip() != "from hashlib import sha256"]
# localizar bloque de futuros
i = 0
def is_meta(l):
    s = l.strip()
    return (s == "" or s.startswith("#!") or s.startswith("# -*-") or s.startswith("#") or
            s.startswith("'''") or s.startswith('"""'))
while i < len(txt) and is_meta(txt[i]):
    i += 1
j = i
while j < len(txt) and txt[j].startswith("from __future__ import"):
    j += 1
txt.insert(j, "from hashlib import sha256")
p.write_text("\n".join(txt) + "\n", encoding="utf-8")
print("OK: sha256 import reubicado en línea", j+1)
PY

echo "➤ create_all() robusto (sin requerir Base)"
python - <<'PY'
import os, sys, importlib, inspect
from pathlib import Path
from sqlalchemy import create_engine
from sqlalchemy.engine import Engine

# Cargar módulo de modelos
m = importlib.import_module('backend.models')

# 1) Engine: intenta m.engine, luego backend.db / backend.database, sino sqlite:///data/app.db
engine = getattr(m, 'engine', None)
if engine is None:
    for mn in ('backend.db', 'backend.database'):
        try:
            md = importlib.import_module(mn)
            engine = getattr(md, 'engine', None) or getattr(md, 'db_engine', None)
            if engine is not None:
                break
        except Exception:
            pass
if engine is None:
    db_path = os.path.join(os.getcwd(), 'data', 'app.db')
    print("WARN: no encontré engine en código; usando sqlite:///%s" % db_path)
    engine = create_engine(f"sqlite:///{db_path}")

# 2) Metadata: intenta Base.metadata; luego SQLModel.metadata; luego detectar por clases con __table__
metadata = None
Base = getattr(m, 'Base', None)
if Base is not None and hasattr(Base, 'metadata'):
    metadata = Base.metadata

if metadata is None:
    try:
        from sqlmodel import SQLModel
        metadata = SQLModel.metadata
    except Exception:
        pass

if metadata is None:
    tables = []
    for name, obj in m.__dict__.items():
        if inspect.isclass(obj) and hasattr(obj, "__table__"):
            tables.append(obj.__table__)
    if tables:
        metadata = tables[0].metadata

if metadata is None:
    raise RuntimeError("No pude determinar metadata (ni Base.metadata, ni SQLModel.metadata, ni clases con __table__). Revisa backend/models.py")

metadata.create_all(bind=engine)
print("create_all() OK contra:", engine.url)
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

echo "➤ Limpiando caches"
find "$BACKEND_DIR" -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true
find "$BACKEND_DIR" -name '*.pyc' -delete 2>/dev/null || true

echo "➤ Arrancando servidor (logs en $LOG)"
nohup python "$REPO_ROOT/run.py" >"$LOG" 2>&1 & disown || true
sleep 2

http() { curl -sS -m 7 -o /dev/null -w "%{http_code}" "$@"; }

echo "➤ Smoke GET /api/health"
echo "   → $(http "${SERVER_URL}/api/health")"

echo "➤ Smoke GET /api/notes"
CODE_G=$(http "${SERVER_URL}/api/notes")
echo "   → ${CODE_G}"

echo "➤ Smoke POST /api/notes"
PAY='{"text":"probando author_fp ultimate","hours":1}'
CODE_P=$(curl -sS -m 10 -H "Content-Type: application/json" -d "$PAY" -o /dev/null -w "%{http_code}" "${SERVER_URL}/api/notes")
echo "   → ${CODE_P}"

if [ "$CODE_P" != "200" ] && [ "$CODE_P" != "201" ]; then
  echo "❌ POST /api/notes falló. Últimas líneas de log:"
  tail -n 120 "$LOG" || true
  exit 1
fi

echo "✅ Todo OK: tablas creadas, server arriba y endpoints respondiendo."
