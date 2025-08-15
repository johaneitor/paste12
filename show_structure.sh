#!/data/data/com.termux/files/usr/bin/bash
# Muestra la estructura del proyecto paste12 con detalles básicos
set -Eeuo pipefail

# Carpeta raíz del proyecto (ajusta si es distinta)
ROOT="$HOME/paste12"

# 1) Comprobación rápida
[[ -d "$ROOT" ]] || { echo "❌  No encuentro $ROOT"; exit 1; }
cd "$ROOT"

echo -e "\n📂  Estructura de directorios en $ROOT"
echo "---------------------------------------"

# Usa 'tree' si está instalado; si no, recurre a find
if command -v tree >/dev/null 2>&1; then
  tree -L 2 -I 'venv|__pycache__|*.pyc|*.db|instance' .
else
  find . -maxdepth 2 -type d \( -name venv -o -name __pycache__ -o -name instance \) -prune -o -print | sed 's|^\./||'
fi

echo -e "\n📝  Archivos clave (primeras líneas)"
echo "-------------------------------------"

# Lista de archivos que suele interesar ver
FILES=(
  "run.py"
  "backend/__init__.py"
  "backend/routes.py"
  "backend/models.py"
  "frontend/index.html"
  "frontend/js/app.js"
)

for f in "${FILES[@]}"; do
  if [[ -f "$f" ]]; then
    echo -e "\n--- $f"
    head -n 10 "$f"
  fi
done

echo -e "\n✅  Resumen completo."

