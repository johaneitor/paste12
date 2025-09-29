#!/usr/bin/env bash
set -euo pipefail
TS="$(date -u +%Y%m%d-%H%M%SZ)"
GR="zoo/_graveyard/$TS"; mkdir -p "$GR"

move_if(){ [[ -e "$1" ]] && { mkdir -p "$(dirname "$GR/$1")"; git mv -k "$1" "$GR/$1" 2>/dev/null || { mkdir -p "$(dirname "$GR/$1")"; mv "$1" "$GR/$1"; }; }; }

# Mover copias antiguas del FE si existen
move_if frontend
move_if backend/frontend

# Mover backups_* ruidosos
for d in backups_*; do [[ -d "$d" ]] && move_if "$d"; done

# Ignorar el graveyard
grep -q '^zoo/_graveyard/' .gitignore 2>/dev/null || echo 'zoo/_graveyard/' >> .gitignore

git add -A
git commit -m "chore(repo): archiva copias duplicadas de FE y backups_* en $GR" || true
echo "✓ Archivado en $GR"
