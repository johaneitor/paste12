#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"
ADMIN="${ADMIN_TOKEN:-}"

# 1) TTL máx (2160 h)
H="$(curl -sI "$BASE/api/notes" || true)"
echo "$H" | awk 'BEGIN{IGNORECASE=1}/^x-max-ttl-hours:/{print}'
echo "TTL limit esperado: 2160h"

# 2) Crear nota larga (12h)
NEW="$(curl -fsS -X POST "$BASE/api/notes" -H 'Content-Type: application/json' -d '{"text":"expiry test …", "hours":12}' | jq -r '.item.id')"
echo "note: $NEW"

# 3) Forzar expiración (requiere token)
if [ -n "$ADMIN" ]; then
  curl -fsS -X POST "$BASE/api/admin/force-expire/$NEW" -H "X-Admin-Token: $ADMIN" | jq .
  curl -fsS -X POST "$BASE/api/admin/expire-now" -H "X-Admin-Token: $ADMIN" | jq .
  # 4) Debe desaparecer del feed y dar 404 en detalle
  curl -fsS "$BASE/api/notes?limit=5" | jq -r '.items[].id' | grep -q "^$NEW$" && echo "✗ sigue en feed" || echo "✓ no aparece en feed"
  code="$(curl -si "$BASE/api/notes/$NEW" | sed -n '1p')"
  echo "$code"
else
  echo "(aviso) ADMIN_TOKEN no provisto → no se prueba force-expire/expire-now"
fi
