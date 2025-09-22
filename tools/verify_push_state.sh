#!/usr/bin/env bash
set -euo pipefail
git fetch origin
echo "== REMOTOS =="
git remote -v | sed 's/^/  /'
echo
echo "== SHAs =="
echo "  Local  HEAD : $(git rev-parse HEAD)"
echo "  Remote HEAD : $(git ls-remote origin -h refs/heads/main | cut -f1)"
echo
echo "== AHEAD/BEHIND =="
git rev-list --left-right --count origin/main...HEAD | awk '{print "  behind=" $1 " ahead=" $2}'
echo
echo "== Último commit local =="
git log -1 --pretty=oneline
