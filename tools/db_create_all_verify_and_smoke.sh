#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"

RUNPY="run.py"
LOG=".tmp/paste12.log"
DB="${PASTE12_DB:-app.db}"

echo "[+] Create ALL (SQLAlchemy) dentro del contexto de la app…"
python - <<'PY'
from importlib import import_module
from sqlalchemy import inspect
try:
    run = import_module("run")
    app = getattr(run, "app", None)
    if app is None:
        raise RuntimeError("No pude importar app desde run.py")
    models = import_module("backend.models")
    db = getattr(models, "db", None)
    if db is None:
        raise RuntimeError("No pude importar db desde backend.models")

    with app.app_context():
        db.create_all()
        insp = inspect(db.engine)
        print("[*] Tablas:", insp.get_table_names())
        if "note" in insp.get_table_names():
            cols = [c["name"] for c in insp.get_columns("note")]
            print("[*] note columnas:", cols)
        else:
            print("[!] Aún no veo tabla 'note'")
except Exception as e:
    print("ERROR create_all:", repr(e))
    raise
PY

# Si hay sqlite3 y existe DB, mostrar esquema rápido
if command -v sqlite3 >/dev/null 2>&1 && [ -f "$DB" ]; then
  echo "[+] PRAGMA table_info(note)"
  sqlite3 "$DB" 'PRAGMA table_info(note);' || true
fi

echo "[+] Reinicio local (nohup)…"
pkill -f "python .*run.py" 2>/dev/null || true
: > "$LOG" || true
nohup python "$RUNPY" >"$LOG" 2>&1 &
sleep 2

PORT="$(grep -Eo '127\.0\.0\.1:[0-9]+' "$LOG" 2>/dev/null | tail -n1 | cut -d: -f2 || echo 8000)"
echo "[i] PORT_LOCAL=$PORT"

echo "[+] URL MAP runtime:"
python - <<'PY'
import importlib
app=getattr(importlib.import_module("run"),"app",None)
rules=[(str(r),sorted([m for m in r.methods if m not in("HEAD","OPTIONS")]),r.endpoint) for r in app.url_map.iter_rules()]
for rule,methods,ep in sorted(rules): print(f"{rule:35s}  {','.join(methods):10s}  {ep}")
has_get = any(r for r in rules if r[0]=="/api/notes" and "GET" in r[1] and r[2].endswith("list_notes"))
has_post= any(r for r in rules if r[0]=="/api/notes" and "POST" in r[1] and r[2].endswith("create_note"))
bad_like= any(r for r in rules if r[0]=="/api/notes" and r[2].endswith("like_note"))
print(f"\nCHECK  /api/notes GET→list_notes:{has_get}  POST→create_note:{has_post}  stray_like_on_/api/notes:{bad_like}")
PY

echo "[+] Smoke GET /api/notes"
curl -i -s "http://127.0.0.1:$PORT/api/notes?page=1" | sed -n '1,80p'
echo
echo "[+] Smoke POST /api/notes"
curl -i -s -X POST -H "Content-Type: application/json" -d '{"text":"db-create-all-ok","hours":24}' "http://127.0.0.1:$PORT/api/notes" | sed -n '1,120p'
echo
