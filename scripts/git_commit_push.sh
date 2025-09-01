set -euo pipefail

# Verifica repo, rama y remoto
if [ ! -d .git ]; then
  echo "Inicializando repo git local..."
  git init
fi

BRANCH="$(git symbolic-ref --quiet --short HEAD || echo main)"
if ! git rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
  # Si no existe la rama (repo recién init), crea main
  BRANCH="main"
  git checkout -b "$BRANCH"
fi

if ! git config user.name >/dev/null 2>&1; then
  echo "⚠ Falta configurar tu identidad git."
  echo "   Ejecutá:  git config user.name 'Tu Nombre' ; git config user.email 'tu@email'"
  exit 2
fi

# Mensaje de commit (argumento o por defecto)
MSG="${1:-feat(runtime): Termux estable con Waitress + shim robusto
- patched_app: CORS, root '/', endpoints /like /report con endpoint único
- anti-choque de blueprints (rename seguro si ya existe 'api')
- serve.sh: autodetección APP_MODULE, Termux→Waitress, Linux→Gunicorn gthread
- scripts: fix_db.sh + smoke.sh
- backend/__init__.py: remove 'from __future__' mal posicionado
}"

# Asegura permisos de ejecución en scripts
chmod +x serve.sh || true
chmod +x scripts/*.sh || true

# Agrega cambios (incluye nuestros archivos)
git add -A

# Evita commit vacío si no hay cambios reales
if git diff --cached --quiet; then
  echo "No hay cambios para commitear."
else
  git commit -m "$MSG"
fi

# Verifica remoto
if ! git remote get-url origin >/dev/null 2>&1; then
  echo "⚠ No tenés 'origin' configurado."
  echo "   Agregá el remoto y empujá manualmente, por ejemplo:"
  echo "   git remote add origin <URL-DEL-REPO>"
  echo "   git push -u origin $BRANCH"
  exit 0
fi

# Push
git push -u origin "$BRANCH"
echo "✔ Push hecho a origin/$BRANCH"
