#!/usr/bin/env bash
set -euo pipefail

# Archivos que podrían estar gitignored pero necesitamos subir
FILES=(
  run.py
  backend/webui.py
  backend/__init__.py
  backend/app.py
  backend/factory.py
)

echo "== git status =="
git status --porcelain || true

echo "== add (force) =="
# Agrega solo los que existan
for f in "${FILES[@]}"; do
  if [ -f "$f" ]; then
    git add -f "$f"
  fi
done

echo "== commit =="
git commit -m "fix(web): serve frontend via blueprint and ensure registration" || true

echo "== push =="
git push origin main
