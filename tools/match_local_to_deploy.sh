#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"

DEPLOY="$(curl -fsS "$BASE/api/deploy-stamp" | sed -n 's/.*"commit": *"\([0-9a-f]\{7,40\}\)".*/\1/p')"
test -n "$DEPLOY" || { echo "No pude leer commit de deploy-stamp"; exit 1; }

CURSHA="$(git rev-parse HEAD | head -c 40)"
BACKUP="backup-$(date -u +%Y%m%d-%H%M%SZ)-$CURSHA"
TAG="deploy/$(printf %.7s "$DEPLOY")"

git branch "$BACKUP" >/dev/null 2>&1 || true
git stash push -u -m "pre-sync $BACKUP" >/dev/null 2>&1 || true
git fetch --all --tags --prune
git cat-file -e "$DEPLOY^{commit}" 2>/dev/null || { echo "El commit $DEPLOY no está accesible desde remotos."; exit 2; }

git tag -f "$TAG" "$DEPLOY" >/dev/null 2>&1 || true
git checkout -B main "$DEPLOY"
git reset --hard "$DEPLOY"

echo "✓ local == producción ($DEPLOY)"
echo "Revertir: git checkout $BACKUP && git reset --hard $BACKUP"
