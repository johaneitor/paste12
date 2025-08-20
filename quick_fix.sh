#!/data/data/com.termux/files/usr/bin/bash
set -e
cd "$(dirname "$0")"

# 1) Backup
cp -p backend/routes.py "backend/routes.py.bak.$(date +%s)"

# 2) Quitar import y el bloque/llamado que rompía el deploy
sed -i -E '/from[[:space:]]+\.[[:space:]]*tasks[[:space:]]+import[[:space:]]+purge_expired_now/d' backend/routes.py
sed -i -E '/^[[:space:]]*try:[[:space:]]*$/d' backend/routes.py
sed -i -E '/purge_expired_now\(/d' backend/routes.py
sed -i -E '/^[[:space:]]*(except|finally)\b.*/d' backend/routes.py

# 3) Chequeo rápido de arranque
python - <<'PY'
from backend import create_app
create_app()
print("✅ create_app() OK")
PY

# 4) Commit + push para forzar redeploy
git add backend/routes.py
git commit -m "fix(routes): eliminar bloque try/purge_expired_now inválido que rompía el import" || true
git push -u origin "$(git rev-parse --abbrev-ref HEAD)"
