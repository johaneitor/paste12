#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ts=$(date +%s)

# 0) Procfile opcional (si prefieres sin render.yaml)
echo 'web: gunicorn "backend:create_app()" -w 4 -k gthread --threads 8 -b 0.0.0.0:$PORT' > Procfile

# 1) render.yaml (servicio web + base de datos Postgres)
cat > render.yaml <<'YAML'
services:
- type: web
  name: paste12
  env: python
  plan: starter
  buildCommand: pip install -r requirements.txt
  startCommand: gunicorn "backend:create_app()" -w 4 -k gthread --threads 8 -b 0.0.0.0:$PORT
  autoDeploy: true
  envVars:
  - key: FLASK_ENV
    value: production
  - key: SECRET_KEY
    generateValue: true
  - key: DISABLE_SCHEDULER
    value: "0"
  # En un solo contenedor el memory:// vale.
  # Si usas más de 1 instancia, cambia a Redis gestionado y pon su URL aquí.
  - key: RATELIMIT_STORAGE_URL
    value: "memory://"
  - fromDatabase:
      name: paste12-db
      property: connectionString
    key: DATABASE_URL

databases:
- name: paste12-db
  plan: starter
YAML

# 2) .renderignore (para no subir la DB local)
cat > .renderignore <<'TXT'
instance/
*.db
*.db-*
*.bak
.paste12.log
.paste12.pid
__pycache__/
TXT

# 3) Git rápido (si no lo tienes)
git init 2>/dev/null || true
git add .
git commit -m "ready for Render: web service + Postgres + Procfile + render.yaml" || true

echo
echo "✅ Archivos de despliegue listos."
echo "➡️  Sube este repo a GitHub/GitLab y crea un servicio Web en Render con 'Use render.yaml'."
echo
echo "IMPORTANTE:"
echo " - Render creará la base 'paste12-db' y pondrá DATABASE_URL automáticamente."
echo " - No definas PORT: Render la inyecta."
echo " - Si más adelante escalas a >1 instancia, cambia RATELIMIT_STORAGE_URL a Redis."
