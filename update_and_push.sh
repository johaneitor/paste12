#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
cd ~/paste12

# (Opcional) ignora backups y scripts locales
if ! grep -q 'render.yaml.bak' .gitignore 2>/dev/null; then
  printf "\n# Backups y scripts locales\n*.bak.*\nrender.yaml.bak.*\nfix_*.sh\n" >> .gitignore
  git add .gitignore
fi

git add -A
git commit -m "chore: actualizar config/render y ajustes" || echo "ℹ️ No hay cambios para commitear"
# Empuja a la rama actual; si falla, renombra a main y reintenta
git push -u origin "$(git rev-parse --abbrev-ref HEAD)" || {
  git branch -M main
  git push -u origin main
}
