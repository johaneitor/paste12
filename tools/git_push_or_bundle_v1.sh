#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: factory_min_fix + full stage + bundle fallback}"

echo "== Stage seguro (forzado) =="
# Archivos núcleo del backend y WSGI
git add -f backend/__init__.py backend/routes.py backend/routes_api_min.py 2>/dev/null || true
git add -f backend/safeguards.py 2>/dev/null || true
git add -f wsgi.py contract_shim.py 2>/dev/null || true

# Todos los tools/*.sh (estén o no .gitignore)
git add -f tools/*.sh 2>/dev/null || true

# Borra/etiqueta archivos eliminados
git add -A

echo "== Commit si hay cambios =="
if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada para commitear"
fi

echo "== Sanity py_compile =="
python -m py_compile backend/__init__.py wsgi.py && echo "py_compile OK"

echo "== Remotos =="
git remote -v || true

echo "== Push =="
if git push -u origin main; then
  echo "✅ Push OK"
  exit 0
fi

echo "⚠️ Push falló. Generando bundle offline…"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
OUT="/sdcard/Download/paste12-main-${TS}.bundle"
# Incluimos todo lo necesario (rama main y tags)
git bundle create "$OUT" --all
echo "🧳 Bundle creado: $OUT"
echo ""
echo "Para aplicar el bundle en otra máquina con red:"
cat <<'GUIDE'
  git clone <tu-repo> paste12 && cd paste12
  # o en un repo existente:
  git remote add offline /ruta/al/bundle 2>/dev/null || true
  git fetch offline
  git merge FETCH_HEAD   # o: git checkout -B main FETCH_HEAD
  git push origin main
GUIDE
