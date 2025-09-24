#!/usr/bin/env bash
set -euo pipefail

req="requirements.txt"
test -f "$req" || printf "%s\n" "# paste12 runtime deps" > "$req"

# Si ya está presente, no lo dupliques
if ! grep -Ei '^\s*flask[-_]?sqlalchemy\s*(==|>=|$)' "$req" >/dev/null; then
  echo "Flask-SQLAlchemy==3.1.1" >> "$req"
  echo "→ Añadido Flask-SQLAlchemy==3.1.1 a $req"
else
  echo "→ Flask-SQLAlchemy ya estaba en $req"
fi

python - <<'PY'
import py_compile; py_compile.compile('wsgi.py', doraise=True); print("✓ py_compile wsgi.py OK")
PY

# Commit quirúrgico (evita workflows)
git checkout -- .github/workflows || true
git restore --staged .github/workflows || true

git add "$req" wsgi.py
git commit -m "ops: agregar Flask-SQLAlchemy a requirements para backend.create_app()"
git push origin main

echo
echo "➡️  En Render (Settings → Start Command), confirmá:"
echo "   gunicorn wsgi:application --chdir /opt/render/project/src -w \${WEB_CONCURRENCY:-2} -k gthread --threads \${THREADS:-4} --timeout \${TIMEOUT:-120} -b 0.0.0.0:\$PORT"
echo "   y que NO haya variables APP_MODULE ni P12_WSGI_* en Environment."
echo "Luego: Clear build cache → Deploy."
