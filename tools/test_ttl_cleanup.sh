#!/usr/bin/env bash
set -euo pipefail

BASE="${1:-}"
if [[ -z "${BASE}" ]]; then
  echo "Uso: tools/test_ttl_cleanup.sh https://tu-app.onrender.com"
  exit 1
fi

TTL_HOURS="${TTL_HOURS:-1}"        # ej: TTL_HOURS=1 tools/test_ttl_cleanup.sh "$BASE"
DBURL="${DATABASE_URL:-}"

note_text="ttl test $(date +%s)-$RANDOM"
echo "BASE=${BASE}"
echo "TTL_HOURS=${TTL_HOURS}"

# Publicar nota
resp="$(curl -sS -X POST "$BASE/api/notes" \
  -H 'Content-Type: application/json; charset=utf-8' \
  --data "{\"text\":\"${note_text}\"}")"
echo "resp=${resp}"
nid="$(printf '%s' "$resp" | sed -nE 's/.*"id":([0-9]+).*/\1/p')"

if [[ -z "${nid}" ]]; then
  echo "ERROR: no pude extraer id de la nota."
  exit 1
fi
echo "note id=${nid}"

# Si no hay DBURL/psql, avisar y salir con 0 (test omitido)
if [[ -z "${DBURL}" ]] || ! command -v psql >/dev/null 2>&1; then
  echo "AVISO: no hay DATABASE_URL y/o psql; omito backdate TTL."
  echo "Sugerencia: export DATABASE_URL='postgres://usuario:pass@host:port/db'"
  exit 0
fi

echo "Backdateando created_at por ${TTL_HOURS}h + 2m usando psql…"
# Intentamos marcar la nota como expirada. Soportamos dos esquemas:
#   a) columnas: created_at/updated_at + expires_at
#   b) solo created_at; el recolector compara NOW() > created_at + TTL
psql "${DBURL}" <<SQL
-- Opción a: si existe expires_at
DO \$\$
BEGIN
  IF EXISTS (SELECT 1
             FROM information_schema.columns
             WHERE table_name='notes' AND column_name='expires_at') THEN
    UPDATE notes
    SET created_at = NOW() - INTERVAL '${TTL_HOURS} hour' - INTERVAL '2 minutes',
        expires_at = NOW() - INTERVAL '1 minute'
    WHERE id = ${nid};
  ELSE
    UPDATE notes
    SET created_at = NOW() - INTERVAL '${TTL_HOURS} hour' - INTERVAL '2 minutes'
    WHERE id = ${nid};
  END IF;
END
\$\$;
SQL

# Disparar un GET para que cualquier “vacuum” en-request se ejecute
curl -sS "$BASE/api/notes?limit=3" >/dev/null || true

# Verificar que la nota ya no esté
code="$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/api/notes/${nid}")"
if [[ "${code}" == "404" ]]; then
  echo "OK: TTL aplicado; nota ${nid} ya no está (404)."
  exit 0
else
  echo "FALLO/INCONCLUSO: la nota ${nid} responde HTTP ${code} (esperado 404)."
  exit 1
fi
