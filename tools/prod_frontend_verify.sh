#!/usr/bin/env bash
set -Eeuo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"

echo "BASE = $BASE"
echo "--- HEAD /api/health ---"
curl -sSI "$BASE/api/health" | head -n 12 || true
echo

for p in / "/js/app.js" "/css/styles.css" "/robots.txt"; do
  echo "--- HEAD $p ---"
  curl -sSI "$BASE$p" | head -n 12 || true
  echo
done

echo "Sugerencias:"
cat <<'TXT'
- Si /api/health es 200 pero / y estáticos dan 404:
  * El deploy aún no tomó el Procfile y/o entrypoint nuevo.
  * Forzá un redeploy rápido con un commit vacío:
      git commit --allow-empty -m "chore: trigger redeploy"
      git push origin main
  * Luego re-ejecutá este script: tools/prod_frontend_verify.sh
TXT
