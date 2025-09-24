#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: frontend overlay + db resilience}"

# Asegura que tools no esté ignorado
if [[ -f .gitignore ]] && ! grep -qE '^!tools/\*\.sh$' .gitignore; then
  echo '!tools/*.sh' >> .gitignore
fi

git add -f contract_shim.py frontend_overlay.py backend/db_resilience.py || true
git add -f tools/*.sh || true
git add frontend/index.html frontend/terms.html frontend/privacy.html 2>/dev/null || true

if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada para commitear"
fi

echo "== prepush gate =="
python -m py_compile contract_shim.py frontend_overlay.py backend/db_resilience.py && echo "✓ py_compile OK"

git push -u origin main
echo "Local : $(git rev-parse HEAD)"
echo "Remote: $(git rev-parse @{u})"
