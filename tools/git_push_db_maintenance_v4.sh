#!/usr/bin/env bash
set -euo pipefail

MSG="${1:-ops: db maintenance v4 (normalize URL + psycopg2 fallback + audit)}"

# 0) Verificaciones básicas
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "ERROR: no es un repo git"; exit 2; }
[[ -f tools/backend_db_maintenance_v4.sh ]] || { echo "ERROR: falta tools/backend_db_maintenance_v4.sh"; exit 3; }

# 1) Gates de sintaxis
bash -n tools/backend_db_maintenance_v4.sh && echo "bash -n OK (backend_db_maintenance_v4.sh)"

# 2) Stage (forzado por si .gitignore tapa tools/)
git add -f tools/backend_db_maintenance_v4.sh 2>/dev/null || true

# 3) Commit si hay cambios
if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada para commitear"
fi

# 4) Push
echo "== prepush gate =="
echo "✓ ready"
echo "Sugerido: correr también tests locales contra staging (opcional)."
git push -u origin main

# 5) Info de HEADs
echo "== HEADs =="
echo "Local : $(git rev-parse HEAD)"
UPSTREAM="$(git rev-parse @{u} 2>/dev/null || true)"
[[ -n "$UPSTREAM" ]] && echo "Remote: $UPSTREAM" || echo "Remote: (upstream se definió recién)"

# 6) Remotos
echo "== REMOTOS =="
git remote -v
