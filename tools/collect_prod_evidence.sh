#!/usr/bin/env bash
# Collect non-destructive evidence from production. Requires appropriate access.
set -Eeuo pipefail
TS=$(date -u +%Y%m%d-%H%M%SZ)
OUT="./p12-e2e-out/logs/${TS}"
mkdir -p "$OUT"

# App logs (example systemd unit name, adjust accordingly)
if command -v journalctl >/dev/null 2>&1; then
  journalctl -u paste12.service --since "24 hours ago" > "$OUT/app_last_24h.log" || true
  journalctl -u paste12.service --since "2 hours ago" > "$OUT/app_last_2h.log" || true
fi

# Postgres diagnostics (requires psql auth via env/PG* vars or .pgpass)
if command -v psql >/dev/null 2>&1; then
  psql -c "SELECT pid, usename, state, query_start, wait_event, query FROM pg_stat_activity ORDER BY query_start DESC LIMIT 50;" > "$OUT/pg_stat_activity.txt" || true
  psql -c "SELECT * FROM pg_locks WHERE NOT granted;" > "$OUT/pg_locks.txt" || true
  psql -c "SELECT * FROM pg_stat_database;" > "$OUT/pg_stat_database.txt" || true
  psql -c "SELECT count(*) FROM pg_stat_activity;" > "$OUT/pg_connections_count.txt" || true
  psql -c "SHOW max_connections;" > "$OUT/pg_max_connections.txt" || true
fi

echo "Evidence collected at $OUT"
