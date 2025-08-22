#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"

RUNPY="run.py"
LOG=".tmp/paste12.log"

echo "[+] Inicializando/migrando DB con SQLAlchemy (create_all + ALTER si falta author_fp)…"
python - <<'PY'
import importlib, sys
from sqlalchemy import inspect, text

mod = importlib.import_module("run")
app = getattr(mod, "app", None)
if app is None:
    print("!! No pude importar app desde run.py"); sys.exit(1)

# localizar db y Note desde tus modelos
db = None; Note = None
for mname in ("backend.models","backend.models.note"):
    try:
        m = importlib.import_module(mname)
        db = getattr(m,"db", db)
        Note = getattr(m,"Note", Note)
    except Exception:
        pass

if db is None or Note is None:
    print("!! No pude importar db/Note desde backend.models"); sys.exit(1)

with app.app_context():
    # Crea todas las tablas declarativas que falten
    db.create_all()

    insp = inspect(db.engine)
    if "note" not in insp.get_table_names():
        print("!! La tabla 'note' sigue sin existir tras create_all(); revisa el modelo.")
    else:
        cols = [c["name"] for c in insp.get_columns("note")]
        if "author_fp" not in cols:
            # Migración mínima: añadir columna con default 'noctx'
            print("[*] Agrego columna author_fp a note…")
            db.session.execute(text('ALTER TABLE note ADD COLUMN author_fp TEXT NOT NULL DEFAULT "noctx"'))
            db.session.commit()
        else:
            print("[*] author_fp ya presente en note.")
print("[✓] DB lista.")
PY

echo "[+] Reiniciando servidor local… (logs en $LOG)"
pkill -f "python .*run.py" 2>/dev/null || true
: > "$LOG" || true
nohup python "$RUNPY" >"$LOG" 2>&1 &
sleep 2
tail -n 80 "$LOG" || true

PORT="$(grep -Eo '127\.0\.0\.1:[0-9]+' "$LOG" 2>/dev/null | tail -n1 | cut -d: -f2 || echo 8000)"
echo "[i] PORT_LOCAL=$PORT"

echo "[+] URL MAP runtime:"
python - <<'PY'
import importlib
app=getattr(importlib.import_module("run"),"app",None)
rules=[(str(r),sorted([m for m in r.methods if m not in("HEAD","OPTIONS")]),r.endpoint) for r in app.url_map.iter_rules()]
for rule,methods,ep in sorted(rules): print(f"{rule:35s}  {','.join(methods):10s}  {ep}")
has_get=any(r for r in rules if r[0]=="/api/notes" and "GET" in r[1])
has_post=any(r for r in rules if r[0]=="/api/notes" and "POST" in r[1])
print(f"\n/api/notes GET:{has_get} POST:{has_post}")
PY

echo "[+] Smoke tests locales:"
echo "--- GET /api/notes"
curl -i -s "http://127.0.0.1:$PORT/api/notes?page=1" | sed -n '1,60p'
echo
echo "--- POST /api/notes"
curl -i -s -X POST -H "Content-Type: application/json" \
     -d '{"text":"init-db-ok","hours":24}' \
     "http://127.0.0.1:$PORT/api/notes" | sed -n '1,100p'
echo
