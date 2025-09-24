#!/usr/bin/env bash
set -Eeuo pipefail

INIT="backend/__init__.py"
WSGI="wsgi.py"

echo "➤ Backups"
cp -a "$INIT" "$INIT.bak.$(date +%s)" 2>/dev/null || true
cp -a "$WSGI" "$WSGI.bak.$(date +%s)" 2>/dev/null || true

python - <<'PY'
from pathlib import Path
import re, sys

p = Path("backend/__init__.py")
s = p.read_text(encoding="utf-8")

# 1) Asegurar import de db en el módulo
if "from flask_sqlalchemy import SQLAlchemy" not in s:
    s = "from flask_sqlalchemy import SQLAlchemy\n" + s
if re.search(r"\bdb\s*=\s*SQLAlchemy\(\)", s) is None:
    s = s.replace("from flask_sqlalchemy import SQLAlchemy",
                  "from flask_sqlalchemy import SQLAlchemy\n\ndb = SQLAlchemy()")

# 2) Insertar db.init_app(app) dentro de create_app(...) antes de 'return app'
pat = re.compile(r"(def\s+create_app\s*\([^)]*\)\s*:\s*)([\s\S]*?)\n(\s*)return\s+app\b")
m = pat.search(s)
if m:
    pre, body, indent = m.group(1), m.group(2), m.group(3)
    if "db.init_app(app)" not in body:
        inject = (
            f"{indent}# -- bind SQLAlchemy --\n"
            f"{indent}try:\n"
            f"{indent}    from . import db  # type: ignore\n"
            f"{indent}    db.init_app(app)\n"
            f"{indent}except Exception:\n"
            f"{indent}    pass\n"
        )
        s = s[:m.start(2)] + body + "\n" + inject + s[m.start(3):]
else:
    # Si no encontramos la factory, no rompemos nada.
    pass

# Guardar
Path("backend/__init__.py").write_text(s, encoding="utf-8")
print("init: db.init_app(app) asegurado en create_app().")
PY

python - <<'PY'
from pathlib import Path
w = Path("wsgi.py")
s = w.read_text(encoding="utf-8")

marker = "# --- DB bind (init_app + create_all) ---"
if marker not in s:
    s = s.rstrip() + f"""

{marker}
# Enlaza SQLAlchemy a la app actual (fallback por si la factory no lo hizo)
try:
    from backend import db  # type: ignore
    db.init_app(app)  # type: ignore[name-defined]
    try:
        with app.app_context():  # type: ignore[name-defined]
            try:
                import backend.models  # aseguro modelos
            except Exception:
                pass
            try:
                db.create_all()
            except Exception:
                pass
    except Exception:
        pass
except Exception:
    pass
"""
    w.write_text(s, encoding="utf-8")
    print("wsgi: fallback db.init_app(app) agregado.")
else:
    print("wsgi: fallback ya presente (ok).")
PY

echo "➤ Commit & push"
git add backend/__init__.py wsgi.py || true
git commit -m "db: asegurar db.init_app(app) en create_app y fallback en wsgi" || true
git push origin main || true

BASE="${BASE:-https://paste12-rmsk.onrender.com}"
echo
echo "➤ Cuando Render aplique el deploy, probá:"
cat <<EOT
BASE="$BASE"
echo "— GET /api/notes?limit=3 —"
curl -sS "\$BASE/api/notes?limit=3" | python -m json.tool || cat

echo
echo "— POST /api/notes —"
curl -sS -D- -H 'Content-Type: application/json' \
  --data '{"text":"hello from prod","hours":24}' \
  "\$BASE/api/notes" | sed -n '1,60p'
EOT
