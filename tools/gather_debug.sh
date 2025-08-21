#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="${1:-$(pwd)}"
cd "$ROOT"

RENDER_URL="https://paste12-rmsk.onrender.com"
LOG=".tmp/paste12.log"
HOOKLOG=".tmp/author_fp_hook.log"
DB="${PASTE12_DB:-app.db}"

echo "=== DETECTAR PUERTO LOCAL ==="
PORT="$(grep -Eo '127\.0\.0\.1:[0-9]+' "$LOG" 2>/dev/null | tail -n1 | cut -d: -f2 || echo 8000)"
echo "PORT_LOCAL=$PORT"
echo

echo "=== RUTAS EN routes.py (decoradores y defs relevantes) ==="
grep -nE '@[A-Za-z_][A-Za-z0-9_]*\.route\(|^def (list_notes|create_note)\(' backend/routes.py || true
echo

echo "=== CONTEXTO ALREDEDOR DE create_note (80 líneas) ==="
CL="$(grep -n '^def create_note' backend/routes.py | head -1 | cut -d: -f1 || echo 1)"
L1=$((CL-30)); [ $L1 -lt 1 ] && L1=1
L2=$((CL+50))
nl -ba backend/routes.py | sed -n "${L1},${L2}p" || true
echo

echo "=== ESQUEMA SQLITE (tabla note) ==="
if command -v sqlite3 >/dev/null 2>&1 && [ -f "$DB" ]; then
  sqlite3 "$DB" 'PRAGMA table_info(note);'
else
  echo "(sin sqlite3 o sin DB local $DB)"
fi
echo

echo "=== HOOK LOG (últimas 80) ==="
tail -n 80 "$HOOKLOG" 2>/dev/null || echo "(sin hook log aún)"
echo

echo "=== LOG APP LOCAL (últimas 120) ==="
tail -n 120 "$LOG" 2>/dev/null || echo "(sin log local aún)"
echo

echo "=== SMOKE LOCAL ==="
echo "--- GET /api/notes?page=1"
curl -i -s "http://127.0.0.1:$PORT/api/notes?page=1" | sed -n '1,40p'
echo
echo "--- POST /api/notes"
curl -i -s -X POST -H "Content-Type: application/json" \
     -d '{"text":"probe-local","hours":24}' \
     "http://127.0.0.1:$PORT/api/notes" | sed -n '1,80p'
echo

echo "=== SMOKE RENDER ==="
echo "--- GET $RENDER_URL/api/notes?page=1"
curl -i -s "$RENDER_URL/api/notes?page=1" | sed -n '1,40p'
echo
echo "--- POST $RENDER_URL/api/notes"
curl -i -s -X POST -H "Content-Type: application/json" \
     -d '{"text":"probe-render","hours":24}' \
     "$RENDER_URL/api/notes" | sed -n '1,80p'
echo
