#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: backend corefix — clean factory + fallback json + health}"

# Gate rápido
python -m py_compile backend/__init__.py

# Stage y push
git add backend/__init__.py || true
git commit -m "$MSG" || echo "ℹ️  Nada para commitear"
echo "== push =="
git push -u origin main

echo "== HEAD =="
git rev-parse HEAD
