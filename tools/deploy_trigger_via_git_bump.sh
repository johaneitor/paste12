#!/usr/bin/env bash
set -euo pipefail
git push -u origin HEAD:main
git commit --allow-empty -m "chore: redeploy bump $(date -u +%Y%m%d-%H%M%SZ)"
git push
echo "OK: bump git push enviado"
