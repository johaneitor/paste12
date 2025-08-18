#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

ts=$(date +%s)
REPO_NAME="${REPO_NAME:-$(basename "$PWD")}"
VISIBILITY="${VISIBILITY:-private}"   # private | public

echo "🚀 Preparando repo para GitHub…"

# 1) Archivos de control (no sobreescribe si ya existen)
[ -f .gitignore ] || cat > .gitignore <<'GIT'
# Python / Flask
__pycache__/
*.py[cod]
*.pyo
*.pyd
*.egg-info/
.env
*.log

# DB local y backups
instance/
*.db
*.db-*
*.bak
*.sqlite3
.paste12.log
.paste12.pid

# Entornos
venv/
.venv/

# SO / editores
.DS_Store
.idea/
.vscode/
*.swp
GIT

[ -f .gitattributes ] || cat > .gitattributes <<'ATTR'
* text=auto eol=lf
ATTR

# 2) Inicializa git si hace falta
if [ ! -d .git ]; then
  git init
  git branch -M main || true
fi

# 3) Config de identidad si falta
if ! git config user.name >/dev/null; then
  read -rp "→ Nombre para git (user.name): " GUN
  git config user.name "$GUN"
fi
if ! git config user.email >/dev/null; then
  read -rp "→ Email para git (user.email): " GEM
  git config user.email "$GEM"
fi

# 4) Asegura que DB/venv no estén trackeados
git rm -r --cached instance 2>/dev/null || true
git ls-files '*.db' '*.db-*' '*.sqlite3' 2>/dev/null | xargs -r git rm --cached
git rm -r --cached venv .venv 2>/dev/null || true

# 5) Commit (solo si hay cambios)
if ! git diff --quiet || ! git diff --cached --quiet; then
  git add -A
  git commit -m "deploy: listo para Render (Flask + Postgres + frontend) [$ts]"
fi

# 6) Crear o usar remoto y hacer push
if git remote get-url origin >/dev/null 2>&1; then
  echo "🔗 Remoto origin detectado: $(git remote get-url origin)"
  git push -u origin main
else
  if command -v gh >/dev/null 2>&1; then
    echo "🔐 Usando GitHub CLI (gh) — creará repo ${VISIBILITY} '${REPO_NAME}' en tu cuenta y hará push…"
    gh repo create "$REPO_NAME" --"$VISIBILITY" --source=. --remote=origin --push
  else
    echo "ℹ️  No se encontró 'gh'. Pegá la URL HTTPS del repo vacío (ej.: https://github.com/USUARIO/${REPO_NAME}.git)"
    read -rp "→ URL del repo en GitHub: " REMOTE_URL
    git remote add origin "$REMOTE_URL" 2>/dev/null || git remote set-url origin "$REMOTE_URL"
    git push -u origin main
  fi
fi

echo "✅ Listo: repo subido a GitHub."
