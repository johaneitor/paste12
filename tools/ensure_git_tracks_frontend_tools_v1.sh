#!/usr/bin/env bash
set -euo pipefail
GI=".gitignore"
[[ -f "$GI" ]] || touch "$GI"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
cp -f "$GI" ".gitignore.$TS.bak"
echo "[git] Backup: .gitignore.$TS.bak"
add() { grep -qxF "$1" "$GI" || echo "$1" >> "$GI"; }
# Asegurar inclusiones
add "!frontend/index.html"
add "!frontend/terms.html"
add "!frontend/privacy.html"
add "!tools/*.sh"
# Evitar ignorar por directorio entero
add "!frontend/"
add "!tools/"
echo "[git] .gitignore actualizado"
git add -f frontend/index.html frontend/terms.html frontend/privacy.html tools/*.sh 2>/dev/null || true
git status --porcelain
