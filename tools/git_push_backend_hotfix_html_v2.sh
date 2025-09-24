#!/usr/bin/env bash
# Uso: tools/git_push_backend_hotfix_html_v2.sh "mensaje"
set -euo pipefail
MSG="${1:-ops: backend hotfix HTML inject v2 (no f-strings)}"

git add -f contract_shim.py tools/inject_html_middleware_v2.sh tools/test_frontend_injection_v2.sh || true

if git diff --cached --quiet; then
  echo "ℹ️  Nada para commitear"
else
  git commit -m "$MSG"
fi

[ -x tools/prepush_gate.sh ] && tools/prepush_gate.sh || true
git push origin main

echo "Local : $(git rev-parse HEAD)"
echo "Remote: $(git ls-remote origin -h refs/heads/main | cut -f1)"
