#!/usr/bin/env bash
set -euo pipefail

# 0) sanity
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "✗ No es un repo git."; exit 1
fi
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "✗ Tenés cambios sin commitear. Hacé commit o 'git stash' y reintentá."; exit 1
fi

# 1) sync remotos
git fetch origin --prune

BASE=origin/main
RANGE="$BASE..HEAD"

# Si ya estás alineado, nada que hacer
if [ -z "$(git rev-list $RANGE 2>/dev/null)" ]; then
  echo "✓ HEAD ya coincide con origin/main"; exit 0
fi

echo "== Analizando commits locales no publicados =="
mapfile -t ALL < <(git rev-list --reverse "$RANGE")
SKIP=()   # los que tocan .github/workflows/
PICK=()   # el resto

for c in "${ALL[@]}"; do
  if git diff-tree --no-commit-id --name-only -r "$c" | grep -qE '^\.github/workflows/'; then
    SKIP+=("$c")
  else
    PICK+=("$c")
  fi
done

echo "• Total       : ${#ALL[@]}"
echo "• A saltar    : ${#SKIP[@]} (commits que tocan .github/workflows/)"
echo "• A reaplicar : ${#PICK[@]}"

# 2) backup
BACKUP="backup-$(date +%Y%m%d-%H%M%S)-$(git rev-parse --short HEAD)"
git branch "$BACKUP" >/dev/null 2>&1 || true
echo "• Backup creado: $BACKUP"

# 3) rebase suave: reset local main a origin/main y cherry-pick limpio
git checkout -B main "$BASE" >/dev/null 2>&1
git reset --hard "$BASE"

for c in "${PICK[@]}"; do
  echo "cherry-pick $c"
  git cherry-pick -x "$c" || { echo "✗ Conflicto en $c. Corregí y corré de nuevo."; exit 2; }
done

# 4) impedir volver a agregar workflows por accidente en ESTA máquina
mkdir -p .github
echo ".github/workflows/" >> .git/info/exclude

echo
echo "✓ Listo. 'main' reconstruida sin commits de workflows."
echo "  Ahora:  git push origin main"
echo "  Revertir localmente si querés: git checkout $BACKUP && git reset --hard $BACKUP"
