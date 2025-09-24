#!/usr/bin/env bash
set -euo pipefail

# 1) Comprobaciones básicas
git rev-parse --is-inside-work-tree >/dev/null

CURBR="$(git rev-parse --abbrev-ref HEAD)"
CURSHA="$(git rev-parse HEAD | head -c 40)"
BACKUP="backup-$(date +%Y%m%d-%H%M%S)-$CURSHA"

echo "· Rama actual: $CURBR"
echo "· SHA actual : $CURSHA"
echo "· Backup     : $BACKUP"

# 2) Guardar estado (reversible)
git branch "$BACKUP" >/dev/null 2>&1 || true
git stash push -u -m "pre-sync $BACKUP" >/dev/null 2>&1 || true

# 3) Sincronizar con origin/main (hard reset seguro)
git fetch origin --prune
git checkout -B main origin/main
git reset --hard origin/main

echo
echo "✓ local == origin/main"
echo "  Revertir: git checkout $BACKUP && git reset --hard $BACKUP"
echo "  Stash   : git stash list | grep pre-sync"
