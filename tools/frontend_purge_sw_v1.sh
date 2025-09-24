#!/usr/bin/env bash
set -euo pipefail
HTML="frontend/index.html"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
[[ -f "$HTML" ]] || { echo "ERROR: falta $HTML"; exit 2; }
cp -f "$HTML" "$HTML.$TS.sw.bak"
echo "[sw-purge] Backup: $HTML.$TS.sw.bak"

# Quitar registros de SW
sed -i -e '/serviceWorker\.register/d' -e '/navigator\.serviceWorker/d' "$HTML" || true
echo "[sw-purge] Quitar refs SW -> OK"
