#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
cd "$(dirname "$0")"

echo "🔎 Chequeando Python y dependencias…"
python -V
pip freeze | grep -i -E 'flask($|[-_])|gunicorn|waitress|flask-compress' || true

echo "🧪 Compilando módulos (detecta errores de sintaxis)…"
python -m compileall -q backend || { echo "❌ Error de compilación en backend"; exit 1; }

echo "🧪 Importando create_app()…"
python - <<'PY'
from backend import create_app
app = create_app()
print("✅ create_app() OK — app WSGI lista")
PY

echo "🚀 Haciendo commit vacío para forzar redeploy…"
git add -A
git commit --allow-empty -m "chore: force redeploy (sanity passed $(date -u +%FT%TZ))" || true
git push -u origin "$(git rev-parse --abbrev-ref HEAD)"

echo
echo "✅ Enviado. Abre Render > tu servicio > Deploys y mira el log."
echo "   Si falla, copia aquí las ~10 primeras líneas del error para corregirlo."
