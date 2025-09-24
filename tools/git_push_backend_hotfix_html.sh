#!/usr/bin/env bash
# Uso: tools/git_push_backend_hotfix_html.sh "mensaje"
set -euo pipefail
MSG="${1:-ops: backend hotfix HTML inject (views + AdSense)}"
git add -f contract_shim.py || true
git add -f tools/inject_html_middleware_v1.sh tools/verify_live_vs_repo_v1.sh tools/cache_bust_and_verify.sh tools/test_exec_after_fix_v3.sh || true

if git diff --cached --quiet; then
  echo "ℹ️  Nada para commitear"; 
else
  git commit -m "$MSG"
fi

# Pre-push gate si existe
[ -x tools/prepush_gate.sh ] && tools/prepush_gate.sh || true

git push origin main
echo "Local : $(git rev-parse HEAD)"
echo "Remote: $(git ls-remote origin -h refs/heads/main | cut -f1)"
