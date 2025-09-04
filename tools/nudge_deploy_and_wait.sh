#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"

# Seguridad: no empujar workflows (GitHub los rechazó antes)
if git ls-files -m -o --exclude-standard | grep -qE '^\.github/workflows/'; then
  echo "✗ Cambios en .github/workflows/ detectados. Stashea o eliminá antes de empujar."
  exit 1
fi

# Alinear origin con local si hace falta
LOCAL="$(git rev-parse HEAD | head -c 40)"
ORIGIN="$(git rev-parse origin/main | head -c 40 || true)"
if [ "$LOCAL" != "$ORIGIN" ]; then
  echo "∙ origin != local → git push origin main"
  git push origin main
fi

# Bump inocuo
STAMP="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
echo "$STAMP" > .deploystamp
git add .deploystamp
git commit -m "deploy: bump $STAMP" >/dev/null
git push origin main

# Espera activa hasta match
TARGET="$(git rev-parse HEAD | head -c 40)"
echo "Esperando a que deploy == $TARGET ..."
for i in $(seq 1 48); do
  DEPLOY="$(curl -fsS "$BASE/api/deploy-stamp" | sed -n 's/.*"commit": *"\([0-9a-f]\{7,40\}\)".*/\1/p' || true)"
  test -n "$DEPLOY" && echo "  intento $i: $DEPLOY"
  [ "$DEPLOY" = "$TARGET" ] && { echo "✓ Deploy igualó HEAD."; exit 0; }
  sleep 5
done
echo "✗ No igualó a tiempo. Revisá Auto-Deploy/branch y logs en Render."
exit 2
