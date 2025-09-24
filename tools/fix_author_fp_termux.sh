#!/usr/bin/env bash
# Termux all-in-one: parchea modelo/rutas, migra DB, reinicia servidor y corre smokes.
set -Eeuo pipefail

REPO_ROOT="$(pwd)"
BACKEND_DIR="${REPO_ROOT}/backend"
MODELS_FILE="${BACKEND_DIR}/models.py"
ROUTES_FILE="${BACKEND_DIR}/routes.py"
DATA_DIR="${REPO_ROOT}/data"
DB_PATH="${DATA_DIR}/app.db"
SERVER_HOST="${SERVER_HOST:-127.0.0.1}"
SERVER_PORT="${SERVER_PORT:-8000}"
SERVER_URL="http://${SERVER_HOST}:${SERVER_PORT}"
LOG="${TMPDIR:-$PREFIX/tmp}/paste12_server.log"

need() { command -v "$1" >/dev/null 2>&1 || { echo "❌ Falta: $1"; exit 1; }; }
say() { echo -e "➤ $*"; }

need python
need sqlite3
need sed
need awk
need curl
mkdir -p "$DATA_DIR"

[[ -f "$MODELS_FILE" ]] || { echo "❌ No encuentro $MODELS_FILE"; exit 1; }
[[ -f "$ROUTES_FILE" ]] || { echo "❌ No encuentro $ROUTES_FILE"; exit 1; }

say "Creando/asegurando DB en $DB_PATH"
[[ -f "$DB_PATH" ]] || sqlite3 "$DB_PATH" "PRAGMA journal_mode=WAL;" >/dev/null

# ─────────────────────────────────────────────────────────
# 1) Patch MODELO: agregar author_fp si falta + asegurar String
# ─────────────────────────────────────────────────────────
if ! grep -qE '^\s*author_fp\s*=' "$MODELS_FILE"; then
  say "Inyectando columna author_fp en models.py"
  cp -f "$MODELS_FILE" "$MODELS_FILE.bak.$(date +%s)"

  # Inserta después de expires_at si existe, o después de timestamp como fallback
  sed -i "
    /class[[:space:]]\+Note[[:space:]]*(Base)[[:space:]]*:/,/^[^[:space:]]/ {
      /expires_at/ {
        n
        i\ \ \ \ author_fp = Column(String(128), nullable=True, index=True)
      }
    }
  " "$MODELS_FILE"

  if ! grep -qE '^\s*author_fp\s*=' "$MODELS_FILE"; then
    sed -i "
      /class[[:space:]]\+Note[[:space:]]*(Base)[[:space:]]*:/,/^[^[:space:]]/ {
        /timestamp/ {
          n
          i\ \ \ \ author_fp = Column(String(128), nullable=True, index=True)
        }
      }
    " "$MODELS_FILE"
  fi

  grep -qE '^\s*author_fp\s*=' "$MODELS_FILE" || { echo "❌ No pude insertar author_fp en models.py"; exit 1; }
else
  say "models.py ya tiene author_fp"
fi

# Asegurar que String esté importado
if ! grep -Eq '^from sqlalchemy .*import .*String' "$MODELS_FILE"; then
  if grep -Eq '^from sqlalchemy .*import .*DateTime' "$MODELS_FILE"; then
    sed -i 's/^\(from sqlalchemy .*import .*DateTime\)/\1, String/' "$MODELS_FILE"
  else
    sed -i '1a from sqlalchemy import String' "$MODELS_FILE"
  fi
  say "Import de String asegurado"
fi

# ─────────────────────────────────────────────────────────
# 2) Patch RUTAS: helper fingerprint + uso en Note(...)
# ─────────────────────────────────────────────────────────
cp -f "$ROUTES_FILE" "$ROUTES_FILE.bak.$(date +%s)"
grep -q 'from hashlib import sha256' "$ROUTES_FILE" || sed -i '1s;^;from hashlib import sha256\n;' "$ROUTES_FILE"

if ! grep -q '_fingerprint_from_request' "$ROUTES_FILE"; then
  say "Agregando helper _fingerprint_from_request a routes.py"
  cat >> "$ROUTES_FILE" <<'PYHELPER'

def _fingerprint_from_request(req):
    ip = (req.headers.get("X-Forwarded-For") or getattr(req, "remote_addr", "") or "").split(",")[0].strip()
    ua = req.headers.get("User-Agent", "")
    raw = f"{ip}|{ua}"
    return sha256(raw.encode("utf-8")).hexdigest()
PYHELPER
fi

# Insertar author_fp en la creación de Note(...) si falta
if ! grep -qE 'author_fp=_fingerprint_from_request' "$ROUTES_FILE"; then
  say "Inyectando author_fp en creación de Note(...)"
  sed -i '
    /Note\s*(\s*$/,/)/ {
      /expires_at/ a\
\ \ \ \ \ \ \ \ author_fp=_fingerprint_from_request(request),
    }
  ' "$ROUTES_FILE" || true
  # Fallback en una sola línea
  grep -qE 'author_fp=_fingerprint_from_request' "$ROUTES_FILE" || \
    sed -i 's/Note(\(.*expires_at[^)]*\))/Note(\1, author_fp=_fingerprint_from_request(request))/' "$ROUTES_FILE"
fi

grep -qE 'author_fp=_fingerprint_from_request' "$ROUTES_FILE" || { echo "❌ No se pudo inyectar author_fp en routes.py"; exit 1; }

# ─────────────────────────────────────────────────────────
# 3) Migración SQLite: columna + índice (si tabla existe)
# ─────────────────────────────────────────────────────────
say "Migrando DB (notes.author_fp + índice)"
HAS_TABLE="$(sqlite3 "$DB_PATH" "SELECT name FROM sqlite_master WHERE type='table' AND name='notes';")" || true
if [[ -n "${HAS_TABLE:-}" ]]; then
  HAS_COL="$(sqlite3 "$DB_PATH" "PRAGMA table_info(notes);" | awk -F'|' '$2=="author_fp"{print 1}')" || true
  [[ "$HAS_COL" == "1" ]] || sqlite3 "$DB_PATH" "ALTER TABLE notes ADD COLUMN author_fp VARCHAR(128);"
  sqlite3 "$DB_PATH" "CREATE INDEX IF NOT EXISTS ix_notes_author_fp ON notes(author_fp);" || true
  say "DB OK (columna e índice listos)"
else
  echo "⚠️ La tabla 'notes' aún no existe en $DB_PATH. La app la creará al iniciar (o usa tu script de init)."
fi

# ─────────────────────────────────────────────────────────
# 4) Reinicio limpio del servidor
# ─────────────────────────────────────────────────────────
say "Matando procesos anteriores (run.py/waitress/flask) si existen"
PIDS="$(ps -o pid,cmd | grep -E 'python .*run\.py|waitress|flask' | grep -v grep | awk '{print $1}' || true)"
[[ -n "${PIDS:-}" ]] && kill -9 $PIDS || true

say "Limpiando __pycache__ y *.pyc"
find "$BACKEND_DIR" -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true
find "$BACKEND_DIR" -name '*.pyc' -delete 2>/dev/null || true

say "Arrancando servidor (logs en $LOG)"
nohup python "$REPO_ROOT/run.py" >"$LOG" 2>&1 & disown || true
sleep 2

# ─────────────────────────────────────────────────────────
# 5) Smokes
# ─────────────────────────────────────────────────────────
http() { curl -sS -m 7 -o /dev/null -w "%{http_code}" "$@"; }

say "Smoke GET /api/health"
CODE_H=$(http "${SERVER_URL}/api/health")
echo "   → ${CODE_H}"

say "Smoke GET /api/notes"
CODE_G=$(http "${SERVER_URL}/api/notes")
echo "   → ${CODE_G}"

say "Smoke POST /api/notes"
PAY='{"text":"probando author_fp termux","hours":1}'
CODE_P=$(curl -sS -m 10 -H "Content-Type: application/json" -d "$PAY" -o /dev/null -w "%{http_code}" "${SERVER_URL}/api/notes")
echo "   → ${CODE_P}"

if [[ "$CODE_P" != "200" && "$CODE_P" != "201" ]]; then
  echo "❌ POST /api/notes no devolvió 200/201. Últimas líneas de log:"
  tail -n 80 "$LOG" || true
  exit 1
fi

say "Verificando que el mapper vea author_fp"
python - <<'PY'
from backend.models import Note
print("mapper_has_author_fp:", 'author_fp' in Note.__mapper__.attrs)
print("table_cols:", list(Note.__table__.columns.keys()))
PY

echo "✅ Listo. author_fp activo en modelo/DB y servidor corriendo en ${SERVER_URL}"
