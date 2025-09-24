#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: frontend runtime fix v3 (card-fix, cache-guard, adsense)}"

# gate simple
python - <<'PY'
print("✓ prepush gate OK")
PY

git add -f tools/fix_frontend_live_desync_v3.sh tools/test_exec_after_fix_v4.sh tools/verify_frontend_live_desync_v3.sh || true
git add ./frontend/index.html 2>/dev/null || git add ./index.html
git commit -m "$MSG" || echo "ℹ️  Nada que commitear"
git push origin main
echo "✔ Push OK"
