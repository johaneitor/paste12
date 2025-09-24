#!/usr/bin/env bash
set -Eeuo pipefail

echo "➤ Fix 1: corregir ruta /api/dbdiag -> /dbdiag en backend/routes.py"
python - <<'PY'
from pathlib import Path, re
p = Path("backend/routes.py")
s = p.read_text(encoding="utf-8")
# Reemplaza @api.route('/api/dbdiag') o "@api/dbdiag" por '/dbdiag'
s2 = re.sub(r"@api\.route\((['\"])\/api\/dbdiag\1", r"@api.route(\1/dbdiag\1)", s)
if s2 != s:
    p.write_text(s2, encoding="utf-8")
    print("routes.py: corregido @api.route('/dbdiag').")
else:
    print("routes.py: ya estaba correcto o no se encontró la firma esperada.")
PY

echo "➤ Fix 2: asegurar db.init_app(app) en backend/entry.py (app efectiva)"
python - <<'PY'
from pathlib import Path
p = Path("backend/entry.py")
s = p.read_text(encoding="utf-8")

block = """
# --- ensure SQLAlchemy is bound to the effective app ---
try:
    from backend import db  # SQLAlchemy() singleton
    with app.app_context():
        try:
            db.init_app(app)  # idempotente si ya estaba configurado
        except TypeError:
            pass
except Exception:
    pass
""".lstrip("\n")

if "db.init_app(app)" not in s:
    s = s.rstrip() + "\n\n" + block
    p.write_text(s, encoding="utf-8")
    print("entry.py: agregado db.init_app(app).")
else:
    print("entry.py: ya tenía db.init_app(app).")
PY

echo "➤ Commit & push"
git add backend/routes.py backend/entry.py || true
git commit -m "fix(api): /dbdiag dentro del blueprint (sin doble /api) + bind db.init_app(app) en backend.entry" || true
git push origin main

echo "✓ Listo. Tras el deploy probá:"
cat <<'SH'
BASE="https://paste12-rmsk.onrender.com"

# Ver que /api/dbdiag ahora exista
curl -sS "$BASE/api/dbdiag" | python -m json.tool

# Probar list y create
curl -sS "$BASE/api/notes?limit=1" | python -m json.tool
curl -sS -D- -H 'Content-Type: application/json' \
  --data '{"text":"hello from prod","hours":24}' \
  "$BASE/api/notes" | sed -n '1,40p'
SH
