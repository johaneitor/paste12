#!/usr/bin/env bash
set -euo pipefail
# Requiere: psql (si usás Postgres) o sqlite3 (si usás SQLite)
# Uso:
#   DATABASE_URL=postgres://... tools/apply_db_patch_author_fp.sh
#   o con SQLite:
#   SQLITE_PATH=./app.db tools/apply_db_patch_author_fp.sh

if [ -n "${DATABASE_URL:-}" ]; then
  echo "== applying on Postgres (DATABASE_URL) =="
  echo "Running db_add_author_fp.sql ..."
  PGPASSWORD="${PGPASSWORD:-}" psql "$DATABASE_URL" -f tools/db_add_author_fp.sql
  echo "OK."
  exit 0
fi

DB="${SQLITE_PATH:-app.db}"
if [ -f "$DB" ]; then
  echo "== applying on SQLite ($DB) =="
  # SQLite ignora IF NOT EXISTS en ALTER limitado, hacemos guardas:
  sqlite3 "$DB" "PRAGMA foreign_keys=off; BEGIN;
  CREATE TABLE IF NOT EXISTS note_tmp AS SELECT *, NULL AS author_fp FROM note;
  DROP TABLE note;
  CREATE TABLE note AS SELECT * FROM note_tmp;
  DROP TABLE note_tmp;
  COMMIT;"
  # índice compuesto aproximado (SQLite no hace DESC en índice de igual modo, pero sirve)
  sqlite3 "$DB" "CREATE INDEX IF NOT EXISTS ix_note_ts_id ON note (timestamp, id);"
  echo "OK."
  exit 0
fi

echo "✗ No DATABASE_URL ni SQLITE_PATH válidos encontrados."
exit 2
