#!/usr/bin/env bash
set -euo pipefail
git add -f backend/static/index.html frontend/index.html
if git diff --cached --quiet; then echo "No hay cambios staged"; exit 0; fi
git commit -m "feat(frontend): index de contingencia (safe-shim v1, sin SW, publish fallback, paginación Link, single-note)"
git push origin main
