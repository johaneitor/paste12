#!/usr/bin/env bash
set -euo pipefail
echo "== REMOTOS =="; git remote -v | sed 's/^/  /'
echo
echo "== SHAs =="; 
echo "  Local  HEAD : $(git rev-parse HEAD)"
echo "  Remote HEAD : $(git ls-remote --heads origin refs/heads/main | awk '{print $1}')"
echo
echo "== Último commit local =="; git log -1 --oneline --decorate
echo
echo "== git show --stat --name-status HEAD =="
git show --stat --name-status --pretty=fuller -1
echo
echo "== Archivos cambiados respecto a origin/main =="
git fetch -q origin main || true
git diff --name-status origin/main..HEAD || true
