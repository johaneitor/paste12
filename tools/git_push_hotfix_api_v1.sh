#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: api/cors safeguards (OPTIONS 204 + GET fallback) + smoke v6}"

git add -f backend/__init__.py tools/patch_api_and_cors_safeguards_v1.sh tools/smoke_api_notes_v6.sh
if [[ -n "$(git status --porcelain)" ]]; then
  # Sanity antes de commitear
  python -m py_compile backend/__init__.py
  git commit -m "$MSG"
else
  echo "ℹ️  Nada para commitear"
fi
echo "== push =="
git push -u origin main
