#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: push over https (fallback)}"

# 0) Verificaciones
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "ERROR: no es repo git"; exit 2; }

# 1) Tomar URL actual y normalizar a HTTPS
URL="$(git config --get remote.origin.url || true)"
if [[ -z "${URL}" ]]; then
  echo "ERROR: no existe 'origin'. Agrega uno: git remote add origin https://github.com/USUARIO/REPO.git"
  exit 3
fi

if [[ "${URL}" =~ ^git@github\.com:(.+)$ ]]; then
  SLUG="${BASH_REMATCH[1]}"
  NEW_URL="https://github.com/${SLUG}"
else
  NEW_URL="${URL}"
fi
[[ "${NEW_URL}" != *.git ]] && NEW_URL="${NEW_URL}.git"

# 2) Opcional: usar token si está disponible (no se persiste en .git/config)
#    Exporta antes:  export GITHUB_TOKEN=xxxxx   (y opcional GITHUB_USERNAME=tu_usuario)
PUSH_URL="${NEW_URL}"
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  USER="${GITHUB_USERNAME:-oauth}"
  PUSH_URL="${NEW_URL/https:\/\//https:\/\/${USER}:${GITHUB_TOKEN}@}"
  echo "ⓘ Usando GITHUB_TOKEN del entorno para este push."
else
  echo "ⓘ Sin GITHUB_TOKEN: Git puede pedir credenciales o usar tu helper."
fi

# 3) Stage + commit si hace falta
git add -A || true
if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "${MSG}"
else
  echo "ℹ️  Nada que commitear (continuo con el push)."
fi

# 4) Forzar remoto origin a HTTPS (evita ruta SSH problemática)
git remote set-url origin "${NEW_URL}"

# 5) Push (HEAD->main)
git push -u "${PUSH_URL}" HEAD:main

# 6) Info
echo "== HEADs =="
echo "Local : $(git rev-parse HEAD)"
UP="$(git rev-parse @{u} 2>/dev/null || true)"; [[ -n "$UP" ]] && echo "Remote: $UP" || echo "Remote no definido aún"
