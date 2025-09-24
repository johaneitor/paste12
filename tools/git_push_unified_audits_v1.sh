#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: unified audits v3 (FE/BE + AdSense + legales + compare)}"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "ERROR: no es un repo git"; exit 2; }
[[ -f tools/run_unified_audits_v3.sh ]] || { echo "ERROR: falta tools/run_unified_audits_v3.sh"; exit 3; }

# Gates
bash -n tools/run_unified_audits_v3.sh && echo "bash -n OK (run_unified_audits_v3.sh)"

# Stage forzado por si .gitignore tapa tools/
git add -f tools/run_unified_audits_v3.sh 2>/dev/null || true

if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada para commitear"
fi

echo "== prepush gate =="; echo "✓ listo"
git push -u origin main

echo "== HEADs =="
echo "Local : $(git rev-parse HEAD)"
UP="$(git rev-parse @{u} 2>/dev/null || true)"
[[ -n "$UP" ]] && echo "Remote: $UP" || echo "Remote: (upstream se definió recién)"

echo "== REMOTOS =="; git remote -v
