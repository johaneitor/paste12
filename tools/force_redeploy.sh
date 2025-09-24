#!/usr/bin/env bash
set -euo pipefail
git commit --allow-empty -m "chore: force redeploy"
git push origin main
echo "Empujado. Cuando Render termine, corré: tools/deploy_sync_check.sh https://paste12-rmsk.onrender.com"
