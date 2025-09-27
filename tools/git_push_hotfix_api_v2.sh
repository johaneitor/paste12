#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: safeguards (OPTIONS 204 + GET fallback) via backend/safeguards.py + rescue indent + smoke v7}"
git add -f backend/__init__.py backend/safeguards.py tools/rescue_indent_and_api_guard_v1.sh tools/smoke_api_notes_v7.sh
if [[ -n "$(git status --porcelain)" ]]; then
  python -m py_compile backend/__init__.py backend/safeguards.py
  git commit -m "$MSG"
else
  echo "ℹ️  Nada para commitear"
fi
git push -u origin main
