#!/usr/bin/env bash
set -euo pipefail
APP="${APP:-}"
[ -n "$APP" ] || { echo "export APP=https://<tu-app>.onrender.com"; exit 1; }

echo "=== [A] Verifica repo/branch en Render ==="
echo " - Service -> Settings -> Git: repo debe ser johaneitor/paste12, branch: main"
echo " - Si no: corrígelo"

echo "=== [B] Start Command (copiar-pegar exacto) ==="
echo "gunicorn wsgi:app -w \${WEB_CONCURRENCY:-2} -k gthread --threads \${THREADS:-4} --bind 0.0.0.0:\$PORT"

echo "=== [C] Clear build cache + Manual Deploy (Latest Commit) ==="
echo " - Settings -> Clear build cache"
echo " - Deploys -> Manual Deploy -> Deploy latest commit"

echo "=== [D] Comprobaciones rápidas ==="
echo "1) /api/diag/import"
curl -sS "$APP/api/diag/import" | jq . || true
echo "2) /api/version"
curl -sS "$APP/api/version" | jq . || true
echo "3) /api/debug-urlmap (notas/ix)"
curl -sS "$APP/api/debug-urlmap" | jq '.rules | map(select(.rule|test("^/api/(notes|ix)/")))' || true
