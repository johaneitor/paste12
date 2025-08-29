#!/usr/bin/env bash
set -euo pipefail
msg="${1:-chore: push all tools + fix Procfile + clean render_entry}"
git add -A
git status --short
git commit -m "$msg" || echo "(no changes to commit)"
git push origin HEAD:main -v
