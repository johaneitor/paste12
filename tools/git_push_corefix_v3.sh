#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: corefix — wsgi export + backend DB url + sanity}"

# gates
bash -n tools/fix_wsgi_export_v1.sh
bash -n tools/patch_backend_db_url_v1.sh
bash -n tools/sanity_entrypoints_v2.sh

# aplicar fixes por si aún no los corriste
tools/fix_wsgi_export_v1.sh
tools/patch_backend_db_url_v1.sh

# sanity
tools/sanity_entrypoints_v2.sh

# stage (forzado)
git add -f wsgi.py backend/__init__.py tools/*.sh

# commit/push
if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada que commitear"
fi
echo "== prepush gate =="; echo "✓ listo"
git push -u origin main

echo "== HEADs =="
echo "Local : $(git rev-parse HEAD)"
UP="$(git rev-parse @{u} 2>/dev/null || true)"; [[ -n "$UP" ]] && echo "Remote: $UP" || true

echo "Sugerencia (Render Start Command):"
echo "  gunicorn wsgi:application --chdir /opt/render/project/src -w \${WEB_CONCURRENCY:-2} -k gthread --threads \${THREADS:-4} --timeout \${TIMEOUT:-120} -b 0.0.0.0:\$PORT"
