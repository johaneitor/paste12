#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"

# 1) Descubro commit de producción
DEPLOY="$(curl -fsS "$BASE/api/deploy-stamp" | sed -n 's/.*"commit": *"\([0-9a-f]\{7,40\}\)".*/\1/p')"
test -n "$DEPLOY" || { echo "✗ No pude leer /api/deploy-stamp"; exit 2; }

# 2) Creo backups de estado remoto y prod por si hay que volver
git fetch --all --tags --prune >/dev/null
REMOTE_MAIN="$(git rev-parse origin/main)"
DEP7="$(printf %.7s "$DEPLOY")"
REM7="$(printf %.7s "$REMOTE_MAIN")"
git tag -f "backup/remote-main-$REM7" "$REMOTE_MAIN" >/dev/null
git tag -f "backup/prod-$DEP7"       "$DEPLOY"      >/dev/null
echo "• Backups: backup/remote-main-$REM7 y backup/prod-$DEP7"

# 3) Me aseguro que mi local está YA en el commit de prod (tú ya lo hiciste, pero dejamos idempotente)
git checkout -B main "$DEPLOY" >/dev/null
git reset --hard "$DEPLOY" >/dev/null

# 4) Forzar push con protección (--force-with-lease) para que origin/main == deploy
echo "• Forzando origin/main -> $DEPLOY (con --force-with-lease)…"
git push --force-with-lease origin "$DEPLOY:main"

# 5) Post-verificación rápida
LOC="$(git rev-parse HEAD)"; ORI="$(git rev-parse origin/main)"
echo "Local : $LOC"
echo "Origin: $ORI"
[ "$LOC" = "$ORI" ] && echo "✓ local == origin" || { echo "✗ local != origin"; exit 3; }

# 6) Chequeo de producción (debería seguir igual que DEPLOY)
DEP="$(curl -fsS "$BASE/api/deploy-stamp" | sed -n 's/.*"commit": *"\([0-9a-f]\{7,40\}\)".*/\1/p')"
echo "Deploy: ${DEP:-<sin valor>}"
[ "$DEP" = "$LOC" ] && echo "✓ deploy == local/origin" || echo "• Nota: Render seguirá en $DEP; está bien (no tocamos runtime)."
echo
echo "Revertir si hiciera falta:"
echo "  git push --force-with-lease origin backup/remote-main-$REM7:main"
