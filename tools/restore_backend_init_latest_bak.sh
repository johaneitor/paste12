#!/usr/bin/env bash
set -euo pipefail
F="backend/__init__.py"
[[ -f "$F" ]] || { echo "ERROR: falta $F"; exit 1; }
TS="$(date -u +%Y%m%d-%H%M%SZ)"
cp -f "$F" "backend/__init__.py.$TS.pre-restore.bak"
echo "[be] Backup: backend/__init__.py.$TS.pre-restore.bak"
LAST="$(ls -1t backend/__init__.py.*.bak 2>/dev/null | head -n1 || true)"
[[ -n "$LAST" ]] || { echo "ERROR: no hay backups *.bak para restaurar"; exit 2; }
cp -f "$LAST" "$F"
python -m py_compile "$F" && echo "[be] py_compile OK" || { echo "[be] py_compile FAIL"; exit 3; }
echo "[be] Restaurado desde: $LAST"
