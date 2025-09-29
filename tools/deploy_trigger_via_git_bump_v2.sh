#!/usr/bin/env bash
set -euo pipefail
# Garantizar que main tenga tu HEAD
git push -u origin HEAD:main
# Commit vacío para forzar redeploy conectado al repo
git commit --allow-empty -m "chore: redeploy bump $(date -u +%Y%m%d-%H%M%SZ)"
git push
echo "OK: bump git push enviado"
