#!/usr/bin/env bash
set -euo pipefail

MSG="${1:-ops: push (fallback SSH->HTTPS)}"

# --- helpers ---
red()  { printf "\033[31m%s\033[0m\n" "$*"; }
grn()  { printf "\033[32m%s\033[0m\n" "$*"; }
ylw()  { printf "\033[33m%s\033[0m\n" "$*"; }

# 0) sanity
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { red "ERROR: no estás en un repo git"; exit 2; }

# 1) commit si hay cambios (por si quedó algo pendiente)
if [[ -n "$(git status --porcelain)" ]]; then
  git add -A
  git commit -m "$MSG" || true
else
  ylw "ℹ️  Nada para commitear"
fi

# 2) info del remoto actual
CUR_URL="$(git remote get-url origin 2>/dev/null || true)"
if [[ -z "${CUR_URL}" ]]; then
  red "ERROR: no existe remoto 'origin'. Agrega uno y reintenta."
  exit 3
fi
echo "origin: ${CUR_URL}"

# 3) intentar push normal
set +e
git push -u origin HEAD:main
RC=$?
set -e
if [[ $RC -eq 0 ]]; then
  grn "✓ Push por SSH/HTTPS del origin OK"
  echo "== HEADs =="
  echo "Local : $(git rev-parse HEAD)"
  echo "Remote: $(git rev-parse @{u})"
  exit 0
fi

ylw "WARN: fallo el push a 'origin' (código $RC). Intento fallback a HTTPS con token..."

# 4) derivar owner/repo de origin
#    admite: git@github.com:owner/repo.git  |  https://github.com/owner/repo.git
if [[ "$CUR_URL" =~ ^git@github\.com:([^/]+/[^.]+)(\.git)?$ ]]; then
  PATH_REPO="${BASH_REMATCH[1]}"
elif [[ "$CUR_URL" =~ ^https://github\.com/([^/]+/[^.]+)(\.git)?$ ]]; then
  PATH_REPO="${BASH_REMATCH[1]}"
else
  red "ERROR: no puedo parsear el remoto origin ($CUR_URL)."
  exit 4
fi

# 5) token: usa GITHUB_TOKEN (recomendado) o GITHUB_PAT
TOKEN="${GITHUB_TOKEN:-${GITHUB_PAT:-}}"
if [[ -z "$TOKEN" ]]; then
  red "ERROR: falta GITHUB_TOKEN en el entorno para fallback HTTPS."
  ylw "Cómo setearlo temporalmente (no se guarda en disco):"
  echo '  export GITHUB_TOKEN=ghp_XXXXXXXXXXXXXXXXXXXXXXXXXXXX'
  echo "y reintenta: tools/git_push_now_with_fallback.sh \"$MSG\""
  exit 5
fi

AUTH_URL="https://x-access-token:${TOKEN}@github.com/${PATH_REPO}.git"

ylw "→ Intento: git push (HTTPS con token) a ${PATH_REPO}"
set +e
git push "$AUTH_URL" HEAD:main
RC=$?
set -e
if [[ $RC -ne 0 ]]; then
  red "ERROR: fallback HTTPS también falló (código $RC)."
  echo "Tips:"
  echo " - Verifica que el token tenga scope 'repo'."
  echo " - Revisa conectividad a https://github.com (curl -I https://github.com)."
  exit $RC
fi

grn "✓ Push por HTTPS con token OK (sin cambiar tu origin)."
echo "== HEADs =="
echo "Local : $(git rev-parse HEAD)"
ylw  "Remote: (consultar en GitHub UI; el push fue por URL autenticada directa)"
