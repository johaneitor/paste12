#!/usr/bin/env bash
set -Eeuo pipefail
BASE="${1:-http://127.0.0.1:8000}"
LIMIT="${2:-2}"

LOG="${TMPDIR:-/data/data/com.termux/files/usr/tmp}/paste12_server.log"
mkdir -p "$(dirname "$LOG")"

echo "➤ Hard restart"
pkill -9 -f "python .*run\\.py" 2>/dev/null || true
pkill -9 -f "waitress" 2>/dev/null || true
pkill -9 -f "gunicorn" 2>/dev/null || true
pkill -9 -f "flask" 2>/dev/null || true
sleep 1
nohup python run.py >"$LOG" 2>&1 & disown || true
sleep 2

echo "➤ Smokes"
tools/recheck_notes_json_v4.sh "$BASE" "$LIMIT"
