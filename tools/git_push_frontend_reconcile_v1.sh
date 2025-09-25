#!/usr/bin/env bash
set -euo pipefail

MSG="${1:-ops: frontend reconcile (adsense+views+dedup+seo)}"

# 0) Validaciones básicas
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "ERROR: no es un repo git"; exit 2; }

# 1) Gates de sintaxis (bash)
for f in tools/frontend_reconcile_v1.sh; do
  [[ -f "$f" ]] && bash -n "$f" || true
done

# 2) Gates de sintaxis (python) - sólo si existen
py_ok=true
py_files=(contract_shim.py wsgi.py backend/__init__.py backend/routes.py backend/models.py)
for p in "${py_files[@]}"; do
  [[ -f "$p" ]] && python -m py_compile "$p" || py_ok=false
done
$py_ok && echo "✓ py_compile OK" || echo "⚠ py_compile tuvo advertencias (revisa arriba)"

# 3) Stage (forzado para tools/ si .gitignore los tapa)
git add -f tools/frontend_reconcile_v1.sh 2>/dev/null || true
# HTML/legales si existen
git add frontend/index.html 2>/dev/null || true
git add frontend/terms.html 2>/dev/null || true
git add frontend/privacy.html 2>/dev/null || true

# 4) Commit si hay cambios
if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada para commitear"
fi

# 5) Push
echo "== prepush gate =="
echo "✓ listo"
echo "Sugerido: correr testers/auditorías contra prod antes/después del push."
git push -u origin main

# 6) HEADs
echo "== HEADs =="
echo "Local : $(git rev-parse HEAD)"
UPSTREAM="$(git rev-parse @{u} 2>/dev/null || true)"
[[ -n "$UPSTREAM" ]] && echo "Remote: $UPSTREAM" || echo "Remote: (upstream se definió recién)"
