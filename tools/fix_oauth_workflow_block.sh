#!/usr/bin/env bash
set -euo pipefail

# Seguridad: no corras con cambios sin commit
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "✗ Tenés cambios sin commitear. Commit o stash primero."; exit 1
fi

git fetch origin --prune

BASE=origin/main
RANGE="$BASE..HEAD"

# Nada que hacer si ya estás alineado
if [ -z "$(git rev-list $RANGE 2>/dev/null)" ]; then
  echo "✓ HEAD ya coincide con origin/main"; exit 0
fi

echo "== Analizando commits locales (no publicados) =="
mapfile -t ALL < <(git rev-list --reverse "$RANGE")
SKIP=()
PICK=()

for c in "${ALL[@]}"; do
  if git diff-tree --no-commit-id --name-only -r "$c" | grep -qE '^\.github/workflows/'; then
    SKIP+=("$c")
  else
    PICK+=("$c")
  fi
done

echo "• Total   : ${#ALL[@]}"
echo "• A saltar: ${#SKIP[@]} (modifican .github/workflows/)"
echo "• A aplicar: ${#PICK[@]}"

BACKUP="backup-$(date +%Y%m%d-%H%M%S)-$(git rev-parse --short HEAD)"
echo "• Backup local en rama: $BACKUP"
git branch "$BACKUP" >/dev/null 2>&1 || true

echo "== Reset a origin/main (solo local) =="
git checkout -B main "$BASE"
git reset --hard "$BASE"

echo "== Reaplicando commits que no tocan workflows =="
for c in "${PICK[@]}"; do
  echo "cherry-pick $c"
  git cherry-pick -x "$c" || { echo "✗ Conflicto en $c. Corrección manual necesaria."; exit 2; }
done

# Evitar re-agregar workflows por accidente en esta máquina
mkdir -p .github
{ echo ".github/workflows/"; } >> .git/info/exclude

echo
echo "✓ Listo. Ahora podés hacer git push origin main"
echo "  Revertir: git checkout $BACKUP && git reset --hard $BACKUP"
