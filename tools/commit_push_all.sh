#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-chore: interactions module update}"
git add -A
git commit -m "$MSG" || true
git push -u --force-with-lease origin "$(git rev-parse --abbrev-ref HEAD)"
