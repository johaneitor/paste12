#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: backend handler fix + unified audit (v2)}"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "ERROR: no es repo git"; exit 2; }

# stage seguro (tools ignorados por .gitignore)
git add -f tools/fix_api_unavailable_v1.sh tools/unified_audit_max6_v2.sh 2>/dev/null || true
# si tocamos backend/__init__.py entrará por el fix
git add backend/__init__.py 2>/dev/null || true

if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada que commitear"
fi

echo "== prepush gate =="
python -m py_compile backend/__init__.py && echo "✓ py_compile backend/__init__.py"
git push -u origin main
echo "== HEAD =="
git rev-parse HEAD
