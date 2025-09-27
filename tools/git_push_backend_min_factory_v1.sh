#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: backend factory hard-reset (routes blueprint + wsgi) + smoke}"

# Gates sintaxis
bash -n tools/hard_reset_backend_factory_v2.sh
bash -n tools/smoke_api_and_front_v1.sh

# Ejecuta reset (idempotente)
tools/hard_reset_backend_factory_v2.sh

# Stage forzado (si .gitignore tapa tools/)
git add -f backend/__init__.py backend/routes.py wsgi.py tools/hard_reset_backend_factory_v2.sh tools/smoke_api_and_front_v1.sh

# Commit/push
if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada que commitear"
fi

echo "== prepush gate =="
python - <<'PY'
import py_compile, sys
for f in ("backend/__init__.py","backend/routes.py","wsgi.py"):
    try:
        py_compile.compile(f, doraise=True)
        print("pyc OK", f)
    except Exception as e:
        print("pyc FAIL", f, "->", e)
        sys.exit(2)
PY

git push -u origin main || true  # en Termux a veces no resuelve github; no es fatal
echo "HEAD local: $(git rev-parse HEAD)"
