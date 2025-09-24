#!/usr/bin/env bash
set -euo pipefail
: "${BASE:?Definí BASE, ej: https://paste12-rmsk.onrender.com}"
: "${ADMIN_TOKEN:?Definí ADMIN_TOKEN}"

err(){ printf "✗ %s\n" "$*" >&2; exit 1; }
ok(){  printf "✓ %s\n" "$*"; }

# Sanity: deploy-stamp y health (si deploy-stamp falla, seguimos)
curl -fsS "$BASE/api/health" >/dev/null && ok "health 200"
curl -fsS "$BASE/api/deploy-stamp" >/dev/null 2>/dev/null || echo "(aviso) /api/deploy-stamp no disponible; ignoro"

# Admin endpoints presentes?
st="$(curl -si -X POST "$BASE/api/admin/expire-now" | sed -n '1p')"
case "$st" in
  *"404"*) err "endpoint /api/admin/expire-now no montado en este deploy";;
  *"403"*) echo "(aviso) /api/admin/expire-now exige token; probando con token...";;
esac

# Crear nota
NEW="$(curl -fsS -X POST "$BASE/api/notes" -H 'Content-Type: application/json' \
  -d '{"text":"expiry e2e test"}' | jq -r '.item.id')"
[ -n "$NEW" ] || err "no pude obtener id de la nota"
ok "nota creada id=$NEW"

# Forzar expiración
curl -fsS -X POST "$BASE/api/admin/force-expire/$NEW" -H "X-Admin-Token: $ADMIN_TOKEN" \
  | jq -e '.ok == true' >/dev/null && ok "force-expire 200"

# Barrido inmediato
curl -fsS -X POST "$BASE/api/admin/expire-now" -H "X-Admin-Token: $ADMIN_TOKEN" \
  | jq -e '.ok == true' >/dev/null && ok "expire-now 200"

# Verificación: no debe estar en feed
if curl -fsS "$BASE/api/notes?limit=200" | jq -r '.items[].id' | grep -q "^$NEW$"; then
  err "la nota $NEW sigue en el feed"
else
  ok "la nota $NEW ya no está en el feed"
fi
