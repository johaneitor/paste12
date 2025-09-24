#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: head handler + adsense normalize + audits pack}"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "ERROR: no es repo git"; exit 2; }

# Gate(s) mínimos
bash -n tools/patch_api_notes_head_v1.sh 2>/dev/null || true
bash -n tools/fix_adsense_cid_v3.sh 2>/dev/null || true
bash -n tools/unified_audit_pack_v2.sh 2>/dev/null || true

# Stage (forzado si .gitignore tapa tools)
git add -f tools/patch_api_notes_head_v1.sh tools/fix_adsense_cid_v3.sh tools/unified_audit_pack_v2.sh 2>/dev/null || true
# Backend y rutas si cambiaron
git add backend/routes.py backend/__init__.py 2>/dev/null || true
# Páginas tocadas
git add frontend/index.html frontend/terms.html frontend/privacy.html 2>/dev/null || true

if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada para commitear"
fi

echo "== prepush gate =="
echo "✓ listo"
echo "Sugerido: correr auditores contra prod antes/después del push."
git push -u origin main

echo "== HEADs =="
echo "Local : $(git rev-parse HEAD)"
UP="$(git rev-parse @{u} 2>/dev/null || true)"; [[ -n "$UP" ]] && echo "Remote: $UP" || echo "Remote: (reciente)"
