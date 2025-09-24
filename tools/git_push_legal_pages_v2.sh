#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: legal pages + routes (terms/privacy) + import wsgi}"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "ERROR: no es repo git"; exit 2; }

# Gates rápidos
bash -n tools/fix_terms_privacy_and_routes_v2.sh
python - <<'PY'
import sys,py_compile
for f in ("backend/routes.py","wsgi.py"):
    try: py_compile.compile(f,doraise=True)
    except Exception as e: 
        print("py_compile FAIL", f, e); sys.exit(1)
print("py_compile OK")
PY

# Stage forzado (por .gitignore)
git add -f frontend/terms.html frontend/privacy.html || true
git add -f backend/routes.py wsgi.py || true
git add -f tools/fix_terms_privacy_and_routes_v2.sh tools/test_legal_pages_v2.sh || true

if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada que commitear"
fi

echo "== prepush gate =="
echo "✓ listo"
echo "Sugerido: correr testers contra prod antes/después del push."

git push -u origin main

echo "== HEADs =="
echo "Local : $(git rev-parse HEAD)"
UP="$(git rev-parse @{u} 2>/dev/null || true)"
[[ -n "$UP" ]] && echo "Remote: $UP" || echo "Remote: (upstream recién definido)"
