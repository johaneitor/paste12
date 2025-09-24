#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: frontend - inserción AdSense en <head>}"

# forzamos a incluir herramientas, aunque .gitignore las oculte
git add -f tools/add_adsense_head.sh tools/test_adsense_head.sh || true

# añade el index modificado
for f in ./index.html ./templates/index.html ./static/index.html ./public/index.html ./frontend/index.html ./web/index.html; do
  [[ -f "$f" ]] && git add -f "$f"
done

git commit -m "$MSG" || echo "ℹ️  Nada que commitear"
echo "== prepush =="
bash -n tools/add_adsense_head.sh && echo "bash -n add_adsense_head.sh OK"
bash -n tools/test_adsense_head.sh && echo "bash -n test_adsense_head.sh OK"
git push origin main
echo "✔ Push OK"
