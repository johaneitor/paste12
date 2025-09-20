#!/usr/bin/env bash
set -euo pipefail
MSG="${MSG:-${1:-ops: backend contract v6 (health JSON, CORS 204, Link, FORM→JSON)}}"

FILES=(
  contract_shim.py
  wsgi.py
  wsgiapp/__init__.py
  tools/test_exec_backend_v6.sh
  tools/git_push_backend_v6.sh
)

if git status --porcelain | awk '{print $2}' | grep -q '^\.github/workflows/'; then
  echo "✗ Cambios en .github/workflows/ bloqueados en este entorno."; exit 1
fi

added=0
for f in "${FILES[@]}"; do
  [ -e "$f" ] && git add -f "$f" && added=1 || true
done
[ "$added" -eq 0 ] && git add -u || true

python - <<'PY'
import py_compile
for p in ("contract_shim.py","wsgi.py"):
    py_compile.compile(p, doraise=True); print("✓ py_compile", p)
PY

git commit -m "$MSG" || { echo "ℹ️  Nada que commitear"; exit 0; }
git push origin main

echo
echo "✓ Push OK. En Render:"
echo "  Start Command:"
echo "    gunicorn wsgi:application --chdir /opt/render/project/src -w \${WEB_CONCURRENCY:-2} -k gthread --threads \${THREADS:-4} --timeout \${TIMEOUT:-120} -b 0.0.0.0:\$PORT"
echo "  (sin APP_MODULE / P12_WSGI_*). Clear build cache + Deploy."
