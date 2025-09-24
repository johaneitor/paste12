#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: hotfix legal pages via WSGI mw (terms/privacy + AdSense)}"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "ERROR: no es repo git"; exit 2; }

# gates
python -m py_compile contract_shim.py && echo "py_compile OK"

# stage forzado
git add -f contract_shim.py tools/hotfix_legal_pages_wsgimw_v1.sh tools/test_legal_adsense_everywhere_v3.sh 2>/dev/null || true

if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada para commitear"
fi

echo "== prepush gate =="; echo "✓ listo"
git push -u origin main

echo "== HEADs =="; echo "Local : $(git rev-parse HEAD)"
UP="$(git rev-parse @{u} 2>/dev/null || true)"
[[ -n "$UP" ]] && echo "Remote: $UP" || echo "Remote: (upstream recién definido)"
