#!/usr/bin/env bash
set -euo pipefail
python - <<'PY'
import py_compile; py_compile.compile("wsgiapp/__init__.py", doraise=True); print("✓ py_compile OK")
PY

git add wsgiapp/__init__.py tools/fix_json_passthrough_like.py || true
git commit -m "chore(core): fix helper _json_passthrough_like (ubicación/indent) + compile gate" || true
git push origin main

# Bump inocuo para gatillar deploy si el entorno lo requiere
STAMP="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
echo "deploy bump ${STAMP}" > .deploystamp
git add .deploystamp
git commit -m "deploy: bump ${STAMP}" || true
git push origin main

echo "== DEPLOY VS HEAD =="
BASE="${1:-https://paste12-rmsk.onrender.com}"
LOCAL="$(git rev-parse HEAD | head -c 40)"
DEPLOY="$(curl -fsS "$BASE/api/deploy-stamp" | sed -n 's/.*"commit": *"\([0-9a-f]\{7,40\}\)".*/\1/p' || true)"
echo "Local:  $LOCAL"
echo "Deploy: ${DEPLOY:-<sin valor>}"
[ -n "$DEPLOY" ] && [ "$LOCAL" = "$DEPLOY" ] && echo "✓ MATCH" || echo "✗ MISMATCH (puede estar construyendo aún)"
