#!/usr/bin/env bash
set -Eeuo pipefail

echo "🔧 Removiendo 'author_fp' del modelo Note (sin tocar la DB)…"
ts=$(date +%s)
cp backend/models.py "backend/models.py.bak.$ts"

python - <<'PY'
import re, pathlib
p = pathlib.Path("backend/models.py")
s = p.read_text(encoding="utf-8")

# 1) Eliminar línea(s) de definición de columna author_fp = db.Column(...)
s = re.sub(r'\n\s*author_fp\s*=\s*db\.Column\([^\n]*\)\s*\n', '\n', s)

# 2) Eliminar referencias sueltas a author_fp en listas/serializadores si quedaran (opcional)
s = re.sub(r'([\'"])author_fp\1\s*,?\s*', '', s)
s = re.sub(r'\bself\.author_fp\b\s*,?\s*', '', s)

p.write_text(s, encoding="utf-8")
print("✓ models.py saneado (sin author_fp)")
PY

# Validación sintaxis
python -m py_compile backend/models.py
echo "✓ Sintaxis OK"

# (Opcional) Gunicorn a 1 worker (SQLite/PG con poca RAM lo agradece)
if [ -f Procfile ]; then
  sed -i 's/^web: .*/web: gunicorn "backend:create_app()" -w 1 -k gthread --threads 8 -b 0.0.0.0:$PORT --timeout 60/' Procfile
fi

echo
echo "🟢 Commit & push:"
echo "   git add backend/models.py Procfile"
echo "   git commit -m 'hotfix(models): eliminar author_fp de Note (columna inexistente en DB)' || true"
echo "   git push -u origin main"
echo
echo "Luego redeploy en Render y prueba:"
echo "   curl -sS https://paste12-rmsk.onrender.com/api/health"
echo "   curl -sS 'https://paste12-rmsk.onrender.com/api/notes?page=1' | head -c 400; echo"
