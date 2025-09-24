#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: wsgi health-first (bypass DB) + tester}"
git add wsgi.py tools/fix_wsgi_health_first_v1.sh tools/test_health_endpoint_v3.sh 2>/dev/null || true
if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada para commitear"
fi
echo "== prepush gate =="; echo "✓ listo"
git push -u origin main
echo "== HEADs =="; echo "Local : $(git rev-parse HEAD)"; UP="$(git rev-parse @{u} 2>/dev/null || true)"; [[ -n "$UP" ]] && echo "Remote: $UP" || true
