#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"

git rev-parse --is-inside-work-tree >/dev/null

DEPLOY="$(curl -fsS "$BASE/api/deploy-stamp" \
  | sed -n 's/.*"commit": *"\([0-9a-f]\{7,40\}\)".*/\1/p')"

test -n "$DEPLOY" || { echo "No pude leer commit de deploy-stamp"; exit 1; }

CURSHA="$(git rev-parse HEAD | head -c 40)"
BACKUP="backup-$(date +%Y%m%d-%H%M%S)-$CURSHA"
TAG="deploy/$(printf %.7s "$DEPLOY")"

echo "· Deploy commit: $DEPLOY"
echo "· Backup        : $BACKUP"
echo "· Tag           : $TAG"

# Backup y stash
git branch "$BACKUP" >/dev/null 2>&1 || true
git stash push -u -m "pre-sync $BACKUP" >/dev/null 2>&1 || true

# Traer commits y asegurarnos que existe el SHA
git fetch --all --tags --prune
git cat-file -e "$DEPLOY^{commit}" 2>/dev/null || {
  echo "El commit $DEPLOY no está alcanzable desde remotos. ¿Segurx que producción y repo apuntan al mismo origen?"
  exit 2
}

# Etiquetar y mover main exactamente al commit de producción
git tag -f "$TAG" "$DEPLOY" >/dev/null 2>&1 || true
git checkout -B main "$DEPLOY"
git reset --hard "$DEPLOY"

echo
echo "✓ local == producción ($DEPLOY)"
echo "  Revertir: git checkout $BACKUP && git reset --hard $BACKUP"
echo "  Tag     : $TAG"
echo "  Stash   : git stash list | grep pre-sync"
