#!/usr/bin/env bash
set -euo pipefail

# Collect application and Postgres evidence (non-destructive) into ./p12-e2e-out/logs/<ts>/
# Usage: export DATABASE_URL=... (optional: PG* envs for psql), then run this script.

TS="$(date -u +%Y%m%d-%H%M%SZ)"
OUT_DIR="./p12-e2e-out/logs/${TS}"
mkdir -p "$OUT_DIR"

echo "== Paste12 evidence collection =="
echo "Output dir: $OUT_DIR"

mask_url(){
  sed -E 's#(postgres(ql)?://[^:]+:)[^@]+#\1*****#g'
}

# 1) App metadata and env snapshot (masked)
{
  echo "# ENV (masked)";
  env | sort | grep -E '^(RENDER|PYTHON_VERSION|DATABASE_URL|SOURCE_VERSION|GIT_COMMIT|TZ|P12_|FLASK_|PORT)=' | mask_url;
  echo;
  echo "# Git status";
  git rev-parse --abbrev-ref HEAD || true;
  git log -n 5 --oneline || true;
} > "$OUT_DIR/app_env.txt" 2>&1

# 2) Try to curl health endpoints (non-destructive)
BASE_URL="${REMOTE_BASE_URL:-}"
if [[ -n "$BASE_URL" ]]; then
  {
    echo "GET $BASE_URL/healthz";
    curl -fsS "$BASE_URL/healthz" || true;
    echo;
    echo "GET $BASE_URL/api/health";
    curl -fsS "$BASE_URL/api/health" || true;
  } > "$OUT_DIR/http_health.txt" 2>&1 || true
fi

# 3) psql diagnostics if available
if command -v psql >/dev/null 2>&1; then
  echo "psql found; collecting Postgres diagnostics" | tee "$OUT_DIR/pg_collect.log"
  {
    echo "-- pg_stat_activity (top 50 new first)";
    psql -X -v ON_ERROR_STOP=1 -c "SELECT pid, usename, state, now()-query_start AS age, wait_event_type, wait_event, left(query,160) AS query FROM pg_stat_activity ORDER BY query_start DESC LIMIT 50;";
    echo;
    echo "-- Locks not granted";
    psql -X -v ON_ERROR_STOP=1 -c "SELECT pid, locktype, mode, granted, relation::regclass AS rel, page, tuple FROM pg_locks WHERE NOT granted;";
    echo;
    echo "-- Connections count and max";
    psql -X -v ON_ERROR_STOP=1 -c "SELECT count(*) AS active FROM pg_stat_activity;";
    psql -X -v ON_ERROR_STOP=1 -c "SHOW max_connections;";
    echo;
    echo "-- Stat database";
    psql -X -v ON_ERROR_STOP=1 -c "SELECT datname, numbackends, xact_commit, xact_rollback, blks_read, blks_hit FROM pg_stat_database;";
  } > "$OUT_DIR/pg_diag.txt" 2>&1 || true
else
  echo "psql not found; skipping DB diagnostics" | tee "$OUT_DIR/pg_collect.log"
fi

# 4) System journalctl (if available, best-effort)
if command -v journalctl >/dev/null 2>&1; then
  journalctl -u paste12.service --since "24 hours ago" > "$OUT_DIR/app_last_24h.log" 2>/dev/null || true
  journalctl -u postgresql --since "24 hours ago" > "$OUT_DIR/pg_last_24h.log" 2>/dev/null || true
fi

echo "Done. Evidence at: $OUT_DIR"
