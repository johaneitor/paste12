#!/usr/bin/env bash
set -euo pipefail
git fetch origin main
# Backup por si acaso
ts="$(date -u +%Y%m%d-%H%M%SZ)"
cp -f wsgiapp/__init__.py "wsgiapp/__init__.py.bak-${ts}" 2>/dev/null || true
# Restaurar sólo este archivo desde origin/main
git show origin/main:wsgiapp/__init__.py > wsgiapp/__init__.py
python -m py_compile wsgiapp/__init__.py
echo "OK: restaurado y compilado wsgiapp/__init__.py desde origin/main"
