#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: backend v9 estable (health JSON, CORS 204, Link, FORM→JSON)}"
git add contract_shim.py wsgi.py wsgiapp/__init__.py tools/*.sh || true
git status --porcelain
if ! git diff --cached --quiet; then
  echo "→ Commit: $MSG"
  git commit -m "$MSG"
else
  echo "ℹ️  Nada que commitear (stage vacío)"
fi
echo "→ Push a origin/main"
git push -u origin main
echo
echo "== Verificación post-push =="
echo "  Local  HEAD : $(git rev-parse HEAD)"
echo "  Remote HEAD : $(git ls-remote --heads origin refs/heads/main | awk '{print $1}')"
