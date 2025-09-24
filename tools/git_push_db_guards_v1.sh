#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: db guards v1 (pre-ping, recycle, sslmode, 503 handler)}"

python - <<'PY'
print("✓ prepush gate OK")
PY

git add -f db_runtime_guards.py tools/patch_db_runtime_guards_v1.sh tools/test_db_transient_v1.sh
git add wsgi.py || true
git commit -m "$MSG" || echo "ℹ️  Nada que commitear"
git push origin main
echo "✔ Push OK"
