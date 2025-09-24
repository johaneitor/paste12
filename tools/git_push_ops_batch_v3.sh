#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: db pooling v4 + post-deploy smoke v2}"
# gates
bash -n tools/patch_db_pooling_v4.sh
bash -n tools/post_deploy_smoke_v2.sh
# stage (forzado si .gitignore tapa tools/)
git add -f tools/patch_db_pooling_v4.sh tools/post_deploy_smoke_v2.sh 2>/dev/null || true
# commit
if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada para commitear"
fi
echo "== prepush gate =="; echo "✓ listo"
git push -u origin main
echo "== HEADs =="; echo "Local : $(git rev-parse HEAD)"; echo "Remote: $(git rev-parse @{u})"
