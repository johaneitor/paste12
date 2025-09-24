#!/usr/bin/env bash
set -euo pipefail
git commit --allow-empty -m "chore: poke redeploy" >/dev/null
git push origin main >/dev/null
echo "OK: commit vacío pushed a main."
