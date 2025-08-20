#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

# 1) Verificaciones
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "❌ No estás dentro de un repositorio git."; exit 1; }

branch="$(git rev-parse --abbrev-ref HEAD)"
remote_url="$(git remote get-url origin 2>/dev/null || true)"
[ -n "$remote_url" ] || { echo "❌ No hay remoto 'origin' configurado."; exit 1; }

echo "📌 Rama: $branch"
echo "🌐 Remoto: $remote_url"

# 2) Endurecer .gitignore (sin duplicar líneas)
touch .gitignore
add_ignore() { grep -qxF "$1" .gitignore || echo "$1" >> .gitignore; }
add_ignore ".env"
add_ignore "instance/*.db"
add_ignore "instance/*.sqlite"
add_ignore "venv/"
add_ignore "__pycache__/"
add_ignore "*.pyc"
add_ignore ".DS_Store"
git add .gitignore || true

# 3) Stage de todo lo NO ignorado
echo "📦 Staging de archivos (respeta .gitignore)…"
git add -A

# 3.1 Salvaguarda por si .env o DB ya estaban trackeados
git restore --staged --worktree --quiet .env 2>/dev/null || true
git restore --staged --worktree --quiet instance/*.db 2>/dev/null || true
git restore --staged --worktree --quiet instance/*.sqlite 2>/dev/null || true

# 4) Commit si hay cambios
if git diff --cached --quiet; then
  echo "✅ No hay cambios para commitear."
else
  git commit -m "chore: agregar scripts de mantenimiento/hotfixes y actualizar ignore"
  echo "✅ Commit creado."
fi

# 5) Push
echo "🚀 Haciendo push a origin/$branch…"
git push -u origin "$branch"

echo "🎉 Listo. Si tu servicio de Render está linkeado al repo, se redeplegará automáticamente."
