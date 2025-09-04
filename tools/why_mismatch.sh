#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"

say(){ printf "%s\n" "$*"; }
hr(){ printf "%s\n" "---------------------------------------------"; }

LOCAL="$(git rev-parse HEAD | head -c 40 2>/dev/null || true)"
ORIGIN="$(git rev-parse origin/main | head -c 40 2>/dev/null || true)"
DEPLOY="$(curl -fsS "$BASE/api/deploy-stamp" | sed -n 's/.*"commit": *"\([0-9a-f]\{7,40\}\)".*/\1/p' || true)"

say "Local : ${LOCAL:-<n/a>}"
say "Origin: ${ORIGIN:-<n/a>}"
say "Deploy: ${DEPLOY:-<sin valor>}"
hr
test -n "${LOCAL:-}"  && test -n "${ORIGIN:-}" && [ "$LOCAL" = "$ORIGIN" ] \
  && say "✓ local == origin" || say "✗ local != origin (hacé git push/pull)"
test -n "${ORIGIN:-}" && test -n "${DEPLOY:-}" && [ "$ORIGIN" = "$DEPLOY" ] \
  && say "✓ origin == deploy (Render al día)" || say "✗ origin != deploy (Render desfasado)"
hr
say "Posibles causas si origin != deploy:"
say "  1) Auto-deploy apagado en Render o apunta a otro repo/branch."
say "  2) El build/deploy falló (Render se quedó en el commit anterior)."
say "  3) El push no gatilló deploy. Solución: hacer un bump de .deploystamp."
say
say "Siguientes pasos sugeridos:"
say "  - Settings en Render: confirmá repo/branch y Auto Deploys=Yes."
say "  - Si falló el deploy: reintentar 'Deploy latest commit' o ver logs."
say "  - O ejecutá: tools/nudge_deploy_and_wait.sh \$BASE"
