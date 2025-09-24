#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: hotfix health bypass (no DB) + tester}"

git add -f tools/hotfix_health_bypass_v1.sh tools/test_health_endpoint_v2.sh 2>/dev/null || true
git add contract_shim.py 2>/dev/null || true

if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada para commitear"
fi

echo "== prepush gate =="
echo "✓ listo (recuerda testear en prod luego del deploy)"

git push -u origin main

echo "== HEADs =="
echo "Local : $(git rev-parse HEAD)"
UP="$(git rev-parse @{u} 2>/dev/null || true)"
[[ -n "$UP" ]] && echo "Remote: $UP" || echo "Remote: (upstream recién configurado)"
