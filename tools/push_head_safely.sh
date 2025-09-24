#!/usr/bin/env bash
set -euo pipefail

# 0) backups reversibles
CURSHA="$(git rev-parse HEAD | head -c 40)"
BACKUP="backup-$(date -u +%Y%m%d-%H%M%S)-$CURSHA"
git branch "$BACKUP" >/dev/null 2>&1 || true
git stash push -u -m "pre-push $BACKUP" >/dev/null 2>&1 || true

# 1) traer remoto y ver estado
git fetch origin --tags --prune
LOCAL="$(git rev-parse HEAD)"
ORIGIN="$(git rev-parse origin/main || echo '')"

echo "Local : $LOCAL"
echo "Origin: ${ORIGIN:-<n/a>}"

# 2) si origin/main existe y difiere, rebaseamos local encima de origin/main
if [[ -n "$ORIGIN" && "$LOCAL" != "$ORIGIN" ]]; then
  echo "== Rebase local -> origin/main =="
  git rebase origin/main
fi

# 3) commit opcional para forzar deploy (no-op si no hay cambios)
STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "$STAMP" > .deploystamp || true
git add .deploystamp || true
git commit -m "deploy: bump $STAMP" || true

# 4) push FF
echo "== git push origin main =="
git push origin main

echo
echo "✓ Push realizado."
echo "Revertir rápido: git checkout $BACKUP && git reset --hard $BACKUP"
echo "Stash guardado:  git stash list | grep pre-push"
