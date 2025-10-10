#!/usr/bin/env bash
set -euo pipefail

BASE="${1:?Uso: $0 BASE_URL}"
TMP="${HOME%/}/tmp/detect_old_$$"
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT

echo "== Ejecutando chequeos básicos (headers/health) =="
tools/check_headers_cors_rate_health_v1.sh "$BASE" || true

echo
echo "== Ejecutando create/view/report (secuencia de verificación) =="
tools/check_create_view_report_v1.sh "$BASE" || true

echo
echo "== Señales de 'sirviendo viejo' (resumen) =="
# Señales:
# - POST /api/notes no devolvió id/u ok
# - /api/health/db ausente o distinto
# - view no deduplicate por X-FP
# - report elimina a la 1
# Vamos a inferir por códigos en outputs previos

# Buscamos en los últimos outputs si hubo errores claros
if curl -sS "$BASE/api/notes" >/dev/null 2>&1 ; then
  echo "OK: GET /api/notes responde."
else
  echo "ERROR: GET /api/notes no responde."
fi

echo
echo "Recomendación:"
echo "- Si alguno de los checks falló: el servidor está sirviendo una versión previa. Hacé merge a main y forzá redeploy (hook/API) y usá tools/deploy_watch_until_v7.sh \"$BASE\" 900 para esperar que remoto == HEAD."
echo "- Si todos los checks OK: proceder con auditorías completas (tools/audit_full_stack_v3.sh \"$BASE\" \"\$HOME/Download\")."
