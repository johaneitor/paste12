#!/usr/bin/env bash
set -euo pipefail

BRANCH="${1:-cursor/apply-security-fixes-and-hardenings-to-paste12-repo-a25f}"
BASE_URL="${2:-https://paste12-rmsk.onrender.com}"
PR_TITLE="${3:-BE: POST /api/notes stable; views idempotent; report consensus; CORS/limits; health; CAP x2}"
PR_BODY_FILE="${4:-docs/runbook.md}"

echo "Branch objetivo: $BRANCH"
echo "Base URL (info only): $BASE_URL"

# 0) mostrar estado rápido
git status --porcelain
echo "HEAD: $(git rev-parse --short HEAD)"

# 1) crear la rama local si no existe
if git show-ref --verify --quiet "refs/heads/${BRANCH}"; then
  echo "La rama ${BRANCH} ya existe localmente; la usaré."
  git checkout "$BRANCH"
else
  echo "Creando rama ${BRANCH} desde HEAD..."
  git checkout -b "$BRANCH"
fi

# 2) compilar Python (fail-fast)
echo "Compilando Python (py_compile)..."
python -m py_compile wsgi.py wsgiapp/__init__.py || { echo "py_compile falló. Revertí cambios o corregí antes de push."; exit 1; }

# 3) push con upstream
echo "Pusheando rama a origin..."
if git push -u origin "$BRANCH"; then
  echo "Push OK"
else
  echo "Push devolvió error. Intentando fallback para workflows..."
  # fallback: intentar quitar workflows del índice y pushear con helper si existe
  if [ -x tools/git_unblock_workflow_and_push_v1.sh ]; then
    echo "Usando tools/git_unblock_workflow_and_push_v1.sh"
    tools/git_unblock_workflow_and_push_v1.sh
  else
    echo "No existe tools/git_unblock_workflow_and_push_v1.sh. Si hay rechazo por workflows, ejecutá manualmente:"
    echo "  git restore --staged .github/workflows/* || true"
    echo "  git reset HEAD .github/workflows/* || true"
    echo "  git checkout -- .github/workflows/* || true"
    echo "  git add -A && git commit -m 'deploy: push sin workflows' || true"
    echo "  git push -u origin $BRANCH"
    exit 1
  fi
fi

# 4) crear PR con gh si está disponible y autenticado
if command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then
    echo "Creando PR con gh..."
    if [ -f "$PR_BODY_FILE" ]; then
      gh pr create --base main --head "$BRANCH" --title "$PR_TITLE" --body-file "$PR_BODY_FILE" && echo "PR creado con gh."
    else
      gh pr create --base main --head "$BRANCH" --title "$PR_TITLE" --body "Patch: $PR_TITLE" && echo "PR creado con gh (body inline)."
    fi
  else
    echo "gh no autenticado. Ejecutá 'gh auth login' o crea PR manualmente en la URL de comparación."
    echo "URL para crear PR manualmente:"
    echo "https://github.com/$(git remote get-url origin | sed -E 's#.*github.com[:/](.+/.+)(\.git)?#\1#')/compare/main...${BRANCH}?expand=1"
  fi
else
  echo "gh CLI no instalada. Crea PR manual usando la URL:"
  echo "https://github.com/$(git remote get-url origin | sed -E 's#.*github.com[:/](.+/.+)(\.git)?#\1#')/compare/main...${BRANCH}?expand=1"
fi

echo "Hecho."
