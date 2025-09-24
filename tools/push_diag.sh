#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"

echo "== Repo =="
git remote -v | sed 's/^/  /'
echo "branch: $(git rev-parse --abbrev-ref HEAD)"

echo "== Status =="
git status -sb || true

echo "== Fetch =="
git fetch origin -q || true
# ahead/behind vs origin/main
read BEHIND AHEAD <<<"$(git rev-list --left-right --count origin/main...HEAD | awk '{print $1, $2}')"
echo "ahead=$AHEAD behind=$BEHIND (vs origin/main)"

if [ "${AHEAD:-0}" -gt 0 ]; then
  echo "→ pushing..."
  git push -v origin HEAD:main
elif [ "${BEHIND:-0}" -gt 0 ]; then
  echo "→ your branch is behind; rebasing..."
  git pull --rebase origin main
  git push origin HEAD:main
else
  echo "→ nothing to push (local == remote)."
fi

echo "== Last commits (local vs remote) =="
echo "LOCAL : $(git rev-parse --short HEAD)  $(git log -1 --pretty=%s)"
echo "REMOTE: $(git rev-parse --short origin/main)  $(git log origin/main -1 --pretty=%s)"

echo "== Deploy stamp =="
curl -fsS "$BASE/api/deploy-stamp" || echo "(deploy-stamp no disponible)"
