#!/usr/bin/env bash
set -euo pipefail

if [[ -f requirements.txt ]]; then
  echo "# rebuild $(date -u +%Y%m%dT%H%M%SZ)" >> requirements.txt
  git add requirements.txt
else
  echo "# rebuild $(date -u +%Y%m%dT%H%M%SZ)" > .rebuild-marker
  git add .rebuild-marker
fi

git commit -m "chore: force full rebuild marker" >/dev/null
git push origin main >/dev/null
echo "OK: marker pushed a main."
