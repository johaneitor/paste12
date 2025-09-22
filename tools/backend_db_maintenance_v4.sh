#!/usr/bin/env bash
set -euo pipefail
#
# Uso:
#   tools/backend_db_maintenance_v4.sh [MAX_NOTES] [BASE]
# Ej:
#   tools/backend_db_maintenance_v4.sh 1000 "https://paste12-rmsk.onrender.com"
#
# Hace:
# - TTL: borra expiradas (expires_at < NOW()).
# - Evicción: deja solo las N más recientes por timestamp DESC.
# - Normaliza DATABASE_URL (postgres:// -> postgresql+psycopg2://) para SQLAlchemy.
# - Si faltan libs Python, intenta fallback con `psql` si está disponible.
# - Auditoría en /sdcard/Download/backend-audit-<ts>.txt

MAX_NOTES="${1:-1000}"
BASE="${2:-}"
OUT_DIR="/sdcard/Download"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
AUD="${OUT_DIR}/backend-audit-${TS}.txt"

log(){ printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }
ensure_dir(){ [[ -d "$1" ]] || mkdir -p "$1" 2>/dev/null || true; }
has(){ command -v "$1" >/dev/null 2>&1; }

ensure_dir "$OUT_DIR"

# -------- Normalización de DATABASE_URL --------
if [[ -z "${DATABASE_URL:-}" ]]; then
  echo "ERROR: falta DATABASE_URL en el entorno" | tee "$AUD"
  exit 2
fi

ORIG_URL="$DATABASE_URL"
PY_URL="$ORIG_URL"
# Para SQLAlchemy:
if [[ "$PY_URL" =~ ^postgres:// ]]; then
  PY_URL="${PY_URL/postgres:\/\//postgresql+psycopg2://}"
fi
export DATABASE_URL="$PY_URL"

# -------- Intento 1: Python (SQLAlchemy + psycopg2) --------
run_python_maint(){
python - <<'PY'
import os, sys
from sqlalchemy import create_engine, text
from sqlalchemy.exc import SQLAlchemyError

dburl = os.environ.get("DATABASE_URL")
if not dburl:
    print("PY-ERROR: falta DATABASE_URL", file=sys.stderr); sys.exit(2)

try:
    eng = create_engine(dburl, pool_pre_ping=True, pool_recycle=300, pool_size=5, max_overflow=10)
except Exception as e:
    print("PY-ERROR: create_engine:", e, file=sys.stderr); sys.exit(3)

expired_deleted = evicted_deleted = total_before = total_after = 0
max_notes = int(os.environ.get("P12_MAX_NOTES", os.environ.get("MAX_NOTES", "1000")))

try:
    with eng.begin() as conn:
        total_before = conn.execute(text("SELECT COUNT(*) FROM notes")).scalar_one()

        r = conn.execute(text("DELETE FROM notes WHERE expires_at IS NOT NULL AND expires_at < NOW()"))
        expired_deleted = r.rowcount or 0

        cnt = conn.execute(text("SELECT COUNT(*) FROM notes")).scalar_one()
        if cnt > max_notes:
            r2 = conn.execute(text("""
                DELETE FROM notes
                WHERE id NOT IN (
                  SELECT id FROM notes ORDER BY timestamp DESC LIMIT :limit
                )
            """), {"limit": max_notes})
            evicted_deleted = r2.rowcount or 0

        total_after = conn.execute(text("SELECT COUNT(*) FROM notes")).scalar_one()

    print(f"OK python | before={total_before} expired={expired_deleted} evicted={evicted_deleted} after={total_after}")
    sys.exit(0)
except SQLAlchemyError as e:
    print("PY-ERROR:", e, file=sys.stderr)
    sys.exit(4)
PY
}
PY_OUT=1
PY_MSG="$(
  run_python_maint 2>&1 || true
)"
if grep -q '^OK python' <<<"$PY_MSG"; then
  PY_OUT=0
fi

# -------- Intento 2: psql (si fallo Python) --------
PSQL_OUT=1
PSQL_MSG=""
if [[ $PY_OUT -ne 0 ]] && has psql; then
  # Usamos la URL original (postgres://) que `psql` entiende bien.
  export DATABASE_URL="$ORIG_URL"
  PSQL_MSG="$(
    {
      echo "INT psql: usando psql por fallback"
      psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM notes WHERE expires_at IS NOT NULL AND expires_at < NOW();" >/dev/null && echo "OK psql TTL"
      psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "WITH c AS (SELECT COUNT(*) AS n FROM notes) SELECT 1;" >/dev/null || true
      # Evicción por límite:
      psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM notes WHERE id NOT IN (SELECT id FROM notes ORDER BY timestamp DESC LIMIT ${MAX_NOTES});" >/dev/null && echo "OK psql EVICT ${MAX_NOTES}"
      # Conteo final:
      CNT="$(psql "$DATABASE_URL" -At -c "SELECT COUNT(*) FROM notes" 2>/dev/null || echo '?')"
      echo "OK psql after_count=${CNT}"
    } 2>&1
  )"
  if grep -q '^OK psql after_count=' <<<"$PSQL_MSG"; then
    PSQL_OUT=0
  fi
fi

# -------- Auditoría --------
{
  echo "== backend_db_maintenance_v4 =="
  echo "ts: ${TS}"
  echo "MAX_NOTES: ${MAX_NOTES}"
  echo "URL(orig): ${ORIG_URL%%\?*}"
  echo "URL(py)  : ${PY_URL%%\?*}"
  echo ""
  if [[ $PY_OUT -eq 0 ]]; then
    echo "$PY_MSG"
  else
    echo "PY_FAIL:"
    echo "$PY_MSG"
  fi
  if [[ -n "$PSQL_MSG" ]]; then
    echo ""
    echo "$PSQL_MSG"
  fi

  # Smoke opcional
  if [[ -n "${BASE}" ]] && has curl; then
    echo ""
    echo "== Smoke (HTTP) =="
    curl -fsS "${BASE%/}/api/health" >/dev/null && echo "OK  - /api/health" || echo "FAIL- /api/health"
    H="$(curl -fsSI "${BASE%/}/api/notes?limit=10" | tr -d '\r' || true)"
    if grep -q '^HTTP/.* 200' <<<"$H"; then echo "OK  - GET /api/notes 200"; else echo "FAIL- GET /api/notes"; fi
    if grep -qi '^link:.*rel="next"' <<<"$H"; then echo "OK  - Link: next"; else echo "WARN- Link next ausente"; fi
  fi
} >"$AUD"

log "Auditoría: $AUD"

# Salida global
if [[ $PY_OUT -eq 0 || $PSQL_OUT -eq 0 ]]; then
  echo "OK: Mantenimiento completado."
  exit 0
else
  echo "FAIL: No se pudo ejecutar mantenimiento (ver auditoría)."
  echo "Sugerencia: pip install 'SQLAlchemy>=2.0' 'psycopg2-binary'  # o instala psql y reintenta"
  exit 1
fi
