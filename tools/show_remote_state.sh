#!/usr/bin/env bash
set -euo pipefail
APP="${APP:?Set APP=https://<tu-app>.onrender.com}"
echo "[diag/import]"; curl -sS "$APP/api/diag/import" | jq . || true
echo "[health]";     curl -sS "$APP/api/health" | jq . || true
echo "[version]";    curl -sS "$APP/api/version" | jq . || true
echo "[map (notes/ix)]"
curl -sS "$APP/api/debug-urlmap" | jq '.rules | map(select(.rule|test("^/api/(notes|ix)/")))' || true
