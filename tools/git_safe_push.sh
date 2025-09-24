#!/usr/bin/env bash
set -euo pipefail
BR=${1:-main}
git fetch origin "$BR" -q
git status -sb || true
git add -f wsgiapp/__init__.py tools/heal_backend_indent_and_routes_v4.py tools/scan_funcs_empty_blocks.py || true
if ! git diff --cached --quiet; then
  git commit -m "fix(wsgi): normaliza indent + _finish/_app canónicos; limpia defs vacías"
fi
git pull --rebase origin "$BR"
git push origin HEAD:"$BR"
