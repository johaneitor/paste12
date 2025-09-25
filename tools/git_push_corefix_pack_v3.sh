#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: corefix pack (auditoría final + stage tools + sanity)}"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "ERROR: no es repo git"; exit 2; }

echo "== Stage deletions/modificaciones detectadas =="
git add -A

echo "== Force-add tools ignorados por .gitignore =="
git add -f tools/*.sh 2>/dev/null || true

echo "== Sanity Python (py_compile) =="
py_ok=1
for f in backend/__init__.py backend/routes.py backend/models.py wsgi.py contract_shim.py; do
  [[ -f "$f" ]] || continue
  if ! python -m py_compile "$f" 2>/dev/null; then
    echo "py_compile FAIL -> $f"; py_ok=0
  fi
done
[[ $py_ok -eq 1 ]] || { echo "Arregla los errores de sintaxis antes del push"; exit 3; }

if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada para commitear"
fi

echo "== prepush =="
echo "✓ listo"
git push -u origin main

echo "== HEADs =="
echo "Local : $(git rev-parse HEAD)"
UP="$(git rev-parse @{u} 2>/dev/null || true)"
[[ -n "$UP" ]] && echo "Remote: $UP" || echo "Remote: (upstream se definió recién)"
