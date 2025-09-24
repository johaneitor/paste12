#!/usr/bin/env bash
# Uso: tools/git_push_frontend_only.sh "mensaje de commit"
set -euo pipefail
MSG="${1:-ops: frontend sync index (views/likes/reports + runtime checks)}"

# Opcional: incluir estos helpers si NO están ignorados
git add -A tools/verify_live_vs_repo_v1.sh tools/cache_bust_and_verify.sh tools/test_exec_after_fix_v3.sh || true

# Frontend
git add -A frontend/index.html || true

# Nada que commitear?
if git diff --cached --quiet; then
  echo "ℹ️  Nada para commitear"; 
else
  git commit -m "$MSG"
fi

# Prepush liviano (si existe)
if [ -x tools/prepush_gate.sh ]; then tools/prepush_gate.sh || true; fi

git push origin main

echo "== HEADs =="
echo "Local : $(git rev-parse HEAD)"
echo "Remote: $(git ls-remote origin -h refs/heads/main | cut -f1)"
