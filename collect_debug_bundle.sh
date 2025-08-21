#!/usr/bin/env bash
set -Eeuo pipefail
ts=$(date +%s)
out="debug_report_$ts.txt"
echo "🔎 Paste12 – Debug bundle — $ts" | tee "$out"

section(){ echo -e "\n\n===== $* =====" | tee -a "$out"; }

section "1) Git y rama"
git branch --show-current | sed 's/^/branch: /' | tee -a "$out"
git remote -v | tee -a "$out"
git status -s | tee -a "$out"
git log --oneline -n 5 | tee -a "$out"
git rev-parse HEAD | sed 's/^/HEAD: /' | tee -a "$out"

section "2) Estructura (profundidad 3)"
if command -v tree >/dev/null 2>&1; then
  tree -a -L 3 -I '.git|__pycache__|*.pyc' | tee -a "$out"
else
  find . -maxdepth 3 -mindepth 1 ! -path '*/.git/*' ! -name '__pycache__' | sort | tee -a "$out"
fi

section "3) Validación sintaxis Python"
python -m py_compile backend/__init__.py backend/routes.py backend/models.py 2>&1 | tee -a "$out" || true

section "4) Grep rápido de backend (paginación/orden/limiter)"
grep -nE 'bp\.get\("/notes"|/api/notes|request\.args\.get\(.page|limit\(|offset\(|order_by|timestamp\.desc|expires_at|@limiter|Limiter' backend/routes.py backend/__init__.py 2>/dev/null | tee -a "$out" || true

section "5) Fragmentos clave de backend/routes.py"
echo "--- cabecera (1..40) ---" | tee -a "$out"
nl -ba backend/routes.py | sed -n '1,40p' | tee -a "$out" || true
echo "--- def list_notes (...) ---" | tee -a "$out"
nl -ba backend/routes.py | awk 'f;/def list_notes\(/ {f=1} /def [a-zA-Z_]+\(/ && NR>1 && f{exit} {print}' | tee -a "$out" || true

section "6) Helpers de vista única y modelos (ViewLog/Unique)"
grep -nE 'class +ViewLog|UniqueConstraint|uq_view|view_date' backend/models.py 2>/dev/null | tee -a "$out" || true

section "7) Frontend: carga paginada y llamadas"
grep -nE 'fetch\(.*/api/notes|page=|IntersectionObserver|addEventListener\(.*scroll' frontend/js/app.js 2>/dev/null | tee -a "$out" || true

section "8) Variables de entorno relevantes (local .env y proceso)"
[ -f .env ] && { echo "-- .env --" | tee -a "$out"; sed -n '1,200p' .env | tee -a "$out"; } || echo "No .env" | tee -a "$out"
python - <<'PY' | tee -a "$out"
import os
keys = ["PAGE_SIZE","MAX_PAGE_SIZE","MAX_NOTES","DATABASE_URL","SQLALCHEMY_DATABASE_URI"]
print({k: os.environ.get(k) for k in keys})
PY

section "9) Inspección de la app Flask (rutas y blueprint /api)"
python - <<'PY' | tee -a "$out"
import os, sys, json
sys.path.insert(0, os.getcwd())
try:
    from backend import create_app
    app = create_app()
    rules = sorted([(r.rule, ",".join(sorted(r.methods - {"HEAD","OPTIONS"})), r.endpoint) for r in app.url_map.iter_rules()], key=lambda x: x[0])
    print("static_folder:", app.static_folder)
    print("\nRutas registradas:")
    for r in rules: print(" - {:<28} | {:<18} | {}".format(*r))
    has_api = any(str(r[0]).startswith("/api/") for r in rules)
    print("\n¿Existe /api/notes?:", any(r[0]=="/api/notes" for r in rules))
    print("¿Hay blueprint /api?:", has_api)
except Exception as e:
    print("❌ No se pudo crear app:", e)
PY

section "10) Smoke test del feed (test_client)"
python - <<'PY' | tee -a "$out"
import os, sys, json, traceback
sys.path.insert(0, os.getcwd())
from datetime import datetime, timezone
try:
    from backend import create_app
except Exception as e:
    print("No create_app:", e); raise SystemExit(0)
app = create_app()
try:
    client = app.test_client()
except Exception as e:
    print("No test_client:", e); raise SystemExit(0)

def try_page(p):
    r = client.get(f"/api/notes?page={p}")
    return r.status_code, r.headers.get("Content-Type"), r.get_data(as_text=True)[:4000]

for p in (1,2,3):
    code, ct, body = try_page(p)
    print(f"\nGET /api/notes?page={p} → {code} ({ct})")
    if code != 200:
        print(body); continue
    try:
        j = json.loads(body)
        notes = j.get("notes") or j.get("data") or []
        print("len(notes) =", len(notes), "has_more =", j.get("has_more"))
        if notes:
            ids = [n.get("id") for n in notes[:5]]
            print("primeros ids:", ids)
    except Exception as e:
        print("⚠️ JSON inesperado:", e, "body:", body[:300])
PY

section "11) Conteo y orden directo en DB (si se puede)"
python - <<'PY' | tee -a "$out"
import os, sys
sys.path.insert(0, os.getcwd())
try:
    from backend import create_app, db
    from backend.models import Note
    app = create_app()
except Exception as e:
    print("No app/db/models:", e); raise SystemExit(0)
with app.app_context():
    try:
        total = db.session.query(Note).count()
        print("total_notas =", total)
        newest = db.session.query(Note).order_by(Note.timestamp.desc()).limit(3).all()
        oldest = db.session.query(Note).order_by(Note.timestamp.asc()).limit(3).all()
        fmt = lambda n: f"id={n.id} ts={getattr(n,'timestamp',None)} likes={getattr(n,'likes',None)} views={getattr(n,'views',None)}"
        print("newest:", [fmt(n) for n in newest])
        print("oldest:", [fmt(n) for n in oldest])
    except Exception as e:
        print("Consulta Note falló:", e)
PY

echo -e "\n\n📄 Reporte guardado en $out"
