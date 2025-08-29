#!/usr/bin/env bash
set -euo pipefail
msg="${1:-chore: restore clean render_entry + tools}"

git add -A
git status --short
git commit -m "$msg" || echo "(no changes to commit)"
git branch -vv
git push origin HEAD:main -v
