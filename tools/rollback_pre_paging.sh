#!/usr/bin/env bash
set -euo pipefail
REMOTE="${REMOTE:-origin}"
TARGET_BRANCH="${TARGET_BRANCH:-main}"
FORCE_MAIN="${1:-}"   # pasa "--force-main" si querés forzar push a main

_red(){ printf "\033[31m%s\033[0m\n" "$*"; }
_grn(){ printf "\033[32m%s\033[0m\n" "$*"; }
_yel(){ printf "\033[33m%s\033[0m\n" "$*"; }

echo "== rollback_pre_paging =="

git fetch --all --prune >/dev/null

# 1) Ubicar commit donde se introdujo la paginación / load-more
CANDIDATES=()

# (a) aparición del smoke/patch de paginación
if git rev-list --all -- scripts/smoke_paging_overlap.sh >/dev/null 2>&1; then
  CANDIDATES+=("$(git rev-list -n1 --all -- scripts/smoke_paging_overlap.sh)")
fi
if git rev-list --all -- scripts/patch_list_notes_before_id.py >/dev/null 2>&1; then
  CANDIDATES+=("$(git rev-list -n1 --all -- scripts/patch_list_notes_before_id.py)")
fi
if git rev-list --all -- tools/patch_load_more.sh >/dev/null 2>&1; then
  CANDIDATES+=("$(git rev-list -n1 --all -- tools/patch_load_more.sh)")
fi

# (b) commits con keywords
KW=(
  "before_id"
  "paginaci"
  "pagination"
  "load more"
  "Cargar más"
  "smoke_paging_overlap"
  "patch_list_notes_before_id"
)
for k in "${KW[@]}"; do
  H="$(git log --all --grep="$k" --format='%H' -n 1 || true)"
  [[ -n "$H" ]] && CANDIDATES+=("$H")
done

if [[ ${#CANDIDATES[@]} -eq 0 ]]; then
  _red "No pude detectar el commit 'problemático'. Mostrándote últimos 30 de $TARGET_BRANCH:"
  git log "$REMOTE/$TARGET_BRANCH" --oneline -n 30
  exit 1
fi

BAD="$(printf '%s\n' "${CANDIDATES[@]}" | head -n1)"
GOOD="$(git rev-parse "${BAD}^")"

echo "BAD = $BAD"
echo "GOOD= $GOOD  (padre de BAD)"

# 2) Crear rama de rollback
BR="rollback/$(date -u +%Y%m%dT%H%M%SZ)"
git checkout -b "$BR" "$REMOTE/$TARGET_BRANCH"

# 3) Restaurar archivos sensibles desde GOOD
git restore --source="$GOOD" -- backend/__init__.py backend/routes.py

# (Opcional) también frontend pre-cambio (descomenta si querés)
# git restore --source="$GOOD" -- backend/frontend/js/app.js backend/frontend/css/actions.css backend/frontend/js/actions.js

# 4) Commit
git add backend/__init__.py backend/routes.py || true
git commit -m "rollback: backend a estado pre-paginación (restore from ${GOOD})" || _yel "Nada que commitear (quizás ya estaba igual)"

# 5) Push branch de rollback
git push "$REMOTE" HEAD:"$BR"

_grn "Rama de rollback publicada: $BR"
echo "Abrí PR de $BR hacia $TARGET_BRANCH y esperá el deploy."
echo

# 6) (Opcional) forzar main si pasaste --force-main
if [[ "$FORCE_MAIN" == "--force-main" ]]; then
  _yel "Forzando $TARGET_BRANCH a $BR (push -f)."
  git checkout "$TARGET_BRANCH"
  git reset --hard "$BR"
  git push -f "$REMOTE" "$TARGET_BRANCH"
  _grn "Force-push hecho a $TARGET_BRANCH."
fi

echo
echo "Post-deploy: corre el smoke rápido:"
echo "  tools/run_system_smoke.sh \"https://paste12-rmsk.onrender.com\""
