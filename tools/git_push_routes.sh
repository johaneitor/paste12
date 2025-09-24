#!/usr/bin/env bash
set -euo pipefail

echo "== Diagnóstico git =="
git rev-parse --abbrev-ref HEAD
git remote -v
echo
echo "-- cambios pendientes --"
git status --porcelain || true
echo

# 1) Asegurar que routes.py se agregó y comiteó
file="backend/routes.py"
if [[ -f "$file" ]]; then
  git add -A
  if git diff --cached --quiet; then
    echo "No hay cambios staged en $file (quizá ya está comiteado)."
  else
    git commit -m "hotfix(routes): limpia bloque residual e indentación" || true
  fi
else
  echo "No existe $file en el repo (nada para commitear)."
fi

# 2) Crear/actualizar una rama hotfix para que el push sea visible
branch="hotfix/routes-import-fix"
git branch -M "$(git rev-parse --abbrev-ref HEAD)" "$(git rev-parse --abbrev-ref HEAD)" >/dev/null 2>&1 || true
git checkout -B "$branch"
git push -u origin "$branch"

echo
echo "✓ Push hecho a rama $branch"
echo "Si tu deploy apunta a 'main', mergeá así:"
echo "  git fetch origin"
echo "  git switch main"
echo "  git merge --no-ff $branch"
echo "  git push origin main"
