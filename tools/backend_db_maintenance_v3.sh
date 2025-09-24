#!/usr/bin/env bash
set -euo pipefail

# Uso:
#   tools/backend_db_maintenance_v3.sh [MAX_NOTES] [BASE]
# Ej:
#   tools/backend_db_maintenance_v3.sh 1000 "https://paste12-rmsk.onrender.com"
#
# Requisitos:
# - Var de entorno DATABASE_URL apuntando a tu Postgres (Render la expone).
# - Paquetes ya instalados en el entorno (sqlalchemy/psycopg2-binary).
#
# Resultados:
# - Auditoría en /sdcard/Download/backend-audit-<ts>.txt

MAX_NOTES="${1:-1000}"
BASE="${2:-}"
OUT_DIR="/sdcard/Download"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
AUD="${OUT_DIR}/backend-audit-${TS}.txt"

log() { printf '%s %s\n' "[$(date -u +%H:%M:%S)]" "$*" ; }
ensure_dir() { [[ -d "$1" ]] || { mkdir -p "$1" 2>/dev/null || true; }; }
need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: falta comando $1"; exit 1; }; }

need python
ensure_dir "$OUT_DIR"

# --- 1) Operaciones DB: TTL + evicción ---
python - <<PY
import os, sys
from datetime import datetime
from sqlalchemy import create_engine, text
from sqlalchemy.exc import SQLAlchemyError

DATABASE_URL = os.environ.get("DATABASE_URL")
if not DATABASE_URL:
    print("ERROR: falta DATABASE_URL en entorno", file=sys.stderr)
    sys.exit(2)

engine = create_engine(DATABASE_URL, pool_pre_ping=True, pool_recycle=300, pool_size=5, max_overflow=10)

expired_deleted = 0
evicted_deleted = 0
total_before = 0
total_after  = 0

with engine.begin() as conn:
    total_before = conn.execute(text("SELECT COUNT(*) FROM notes")).scalar_one()

    # TTL: borrar expiradas
    r = conn.execute(text("DELETE FROM notes WHERE expires_at IS NOT NULL AND expires_at < NOW()"))
    expired_deleted = r.rowcount or 0

    # Evicción por tope
    max_notes = int(os.environ.get("P12_MAX_NOTES", os.environ.get("MAX_NOTES", str(${MAX_NOTES}))))
    cnt = conn.execute(text("SELECT COUNT(*) FROM notes")).scalar_one()
    if cnt > max_notes:
        # Mantener las más recientes por timestamp desc
        evq = text("""
            DELETE FROM notes
            WHERE id NOT IN (
              SELECT id FROM notes ORDER BY timestamp DESC LIMIT :limit
            )
        """)
        r2 = conn.execute(evq, {"limit": max_notes})
        evicted_deleted = r2.rowcount or 0

    total_after = conn.execute(text("SELECT COUNT(*) FROM notes")).scalar_one()

print("|total_before|", total_before)
print("|expired_deleted|", expired_deleted)
print("|evicted_deleted|", evicted_deleted)
print("|total_after|", total_after)
PY
# Guardar resultados de Python (stdout) para el reporte
PY_OUT="$?"
# stdout ya se imprime; volvemos a capturarlo re-ejecutando para el archivo
PY_RPT="$(python - <<PY
import os, sys
from datetime import datetime
from sqlalchemy import create_engine, text
DATABASE_URL = os.environ.get("DATABASE_URL")
engine = create_engine(DATABASE_URL, pool_pre_ping=True, pool_recycle=300)
with engine.begin() as conn:
    tb = conn.execute(text("SELECT COUNT(*) FROM notes")).scalar_one()
print("notes_count:", tb)
PY
)"

# --- 2) Auditoría base ---
{
  echo "== Backend maintenance audit =="
  echo "ts: ${TS}"
  if [[ "${PY_OUT}" -eq 0 ]]; then
    echo "OK  - mantenimiento DB ejecutado"
  else
    echo "FAIL- mantenimiento DB (rc=${PY_OUT})"
  fi
  echo "${PY_RPT}"
} >"$AUD"

# --- 3) Smoke opcional contra BASE ---
if [[ -n "${BASE}" ]]; then
  if command -v curl >/dev/null 2>&1; then
    {
      echo ""
      echo "== Smoke =="
      curl -fsS "${BASE%/}/api/health" >/dev/null && echo "OK  - /api/health" || echo "FAIL- /api/health"
      H=$(curl -fsSI "${BASE%/}/api/notes?limit=10" | tr -d '\r')
      echo "$H" | grep -q '^HTTP/.* 200' && echo "OK  - GET /api/notes 200" || echo "FAIL- GET /api/notes"
      echo "$H" | grep -qi '^link:.*rel="next"' && echo "OK  - Link: next" || echo "WARN- Link next ausente"
    } >>"$AUD" 2>&1
  fi
fi

log "Auditoría: $AUD"
echo "OK: Backend mantenimiento completado."
