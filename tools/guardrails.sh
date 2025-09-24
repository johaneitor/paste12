#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"
LOG=".tmp/paste12.log"; mkdir -p .tmp

say(){ printf "\n[+] %s\n" "$*"; }

say "Compilo .py"
python -m compileall -q backend run.py

say "Reinicio app (nohup)…"
pkill -f "python .*run.py" 2>/dev/null || true
: > "$LOG" || true
nohup python run.py >"$LOG" 2>&1 &
sleep 2

say "URL map: duplicados y contrato /api/notes"
python - <<'PY'
import importlib, sys
mod = importlib.import_module("run")
app = getattr(mod, "app", None)
if not app:
    print("!! no app"); sys.exit(1)

from collections import defaultdict
by_ep = defaultdict(list)
for r in app.url_map.iter_rules():
    by_ep[r.endpoint].append(r)

dups = {k:v for k,v in by_ep.items() if len(v)>1}
if dups:
    print("!! Endpoints duplicados:")
    for k,v in dups.items():
        print("  -", k, [f"{r.rule}:{sorted(r.methods)}" for r in v])

has_get  = any(r.rule=="/api/notes" and "GET"  in r.methods for r in app.url_map.iter_rules())
has_post = any(r.rule=="/api/notes" and "POST" in r.methods for r in app.url_map.iter_rules())
wrong_like = any(r.rule=="/api/notes" and r.endpoint.endswith("like_note") for r in app.url_map.iter_rules())
print("CHECK /api/notes  GET:", has_get, " POST:", has_post, " like-note-bound:", wrong_like)
if wrong_like or not (has_get and has_post):
    sys.exit(2)
PY

say "DB: create_all + columna author_fp (sqlite)"
python - <<'PY'
import importlib
mod = importlib.import_module("run")
app = getattr(mod, "app", None)
db  = getattr(importlib.import_module("backend.models"), "db", None)
if app and db:
    with app.app_context():
        db.create_all()
PY

DB="${PASTE12_DB:-app.db}"
if command -v sqlite3 >/dev/null 2>&1 && [ -f "$DB" ]; then
  if ! sqlite3 "$DB" 'PRAGMA table_info(note);' | awk -F'|' '{print $2}' | grep -q '^author_fp$'; then
    echo "!! Falta author_fp → ALTER"
    sqlite3 "$DB" 'ALTER TABLE note ADD COLUMN author_fp TEXT NOT NULL DEFAULT "noctx";'
    sqlite3 "$DB" 'CREATE INDEX IF NOT EXISTS idx_note_author_fp ON note(author_fp);'
  fi
fi

say "Humos /api/notes"
PORT="$(grep -Eo '127\.0\.0\.1:[0-9]+' "$LOG" | tail -n1 | cut -d: -f2 || echo 8000)"
echo "--- GET"
curl -s -i "http://127.0.0.1:$PORT/api/notes?page=1" | sed -n '1,25p'
echo "--- POST"
curl -s -i -X POST -H "Content-Type: application/json" -d '{"text":"guardrails","hours":24}' "http://127.0.0.1:$PORT/api/notes" | sed -n '1,40p'
echo
echo "[✓] guardrails OK"
