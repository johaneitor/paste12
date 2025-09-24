#!/usr/bin/env bash
set -euo pipefail

echo "→ Limpiando cambios en .github/workflows/ (no los vamos a commitear)…"
# Intenta resetear tanto en working tree como en index; ignora errores si no aplica
git checkout -- .github/workflows || true
git restore --staged .github/workflows || true

echo "→ Preparando stage solo con el takeover…"
# Asegura que wsgi.py quede staged
git add -f wsgi.py

# Si estos archivos existen en el repo, marcarlos como eliminados (ya fueron renombrados a .bak por el anterior script)
for f in render.yaml Procfile start_render.sh; do
  if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
    echo "   - removiendo del repo: $f"
    git rm -f "$f"
  fi
done

echo "→ Commit y push…"
git commit -m "ops: takeover efectivo — usar wsgi:application y eliminar blueprint/Procfile del repo"
git push origin main

echo "✓ Listo. Ahora en Render:"
echo "   Settings → Start Command ="
echo "     gunicorn wsgi:application --chdir /opt/render/project/src -w \${WEB_CONCURRENCY:-2} -k gthread --threads \${THREADS:-4} --timeout \${TIMEOUT:-120} -b 0.0.0.0:\$PORT"
echo "   (y sin APP_MODULE / P12_WSGI_* en Environment) → Clear build cache → Deploy"
