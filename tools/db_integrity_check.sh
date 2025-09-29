#!/usr/bin/env bash
set -euo pipefail
DB="${1:-data.sqlite3}"
sqlite3 "$DB" 'PRAGMA quick_check;'
sqlite3 "$DB" ".schema notes" | grep -E 'likes|views|reports' >/dev/null \
  && echo "OK: columnas likes/views/reports presentes" \
  || { echo "WARN: faltan columnas en notes"; exit 1; }
