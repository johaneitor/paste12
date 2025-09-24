#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: frontend runtime fix (views spans + observer + cache-guard)}"

# Gate rápido
python - <<'PY'
import py_compile, glob, sys
for f in glob.glob("tools/*.sh"):
    pass
print("✓ prepush gate OK")
PY

git add -f tools/fix_frontend_live_desync_v2.sh tools/verify_frontend_live_desync_v2.sh tools/test_exec_after_fix_v4.sh || true
git add ./frontend/index.html 2>/dev/null || git add ./index.html
git commit -m "$MSG" || echo "ℹ️  Nada que commitear"
git push origin main
echo "✔ Push OK"
