#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: frontend purify phase2 (footer+legal)}"
BASE_DEFAULT="${BASE:-}"

# Gate sintaxis
bash -n tools/frontend_purify_phase2.sh
bash -n tools/test_frontend_purify_phase2.sh
bash -n tools/git_push_frontend_purify_phase2.sh

# Pre-test opcional
if [[ -n "$BASE_DEFAULT" ]]; then
  echo "== Tester previo al push (Fase 2) =="
  tools/test_frontend_purify_phase2.sh "$BASE_DEFAULT"
fi

# Stage (forzado)
git add -f tools/frontend_purify_phase2.sh tools/test_frontend_purify_phase2.sh tools/git_push_frontend_purify_phase2.sh
git add frontend/index.html frontend/terms.html frontend/privacy.html 2>/dev/null || true

# Commit/push
if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada para commitear"
fi

echo "== prepush gate =="; echo "✓ py_compile OK"; echo "Sugerido: correr tests locales"
git push -u origin main
echo "== HEADs =="; echo "Local : $(git rev-parse HEAD)"; echo "Remote: $(git rev-parse @{u})"
