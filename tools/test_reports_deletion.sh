#!/usr/bin/env bash
set -euo pipefail

BASE="${1:-}"
if [[ -z "${BASE}" ]]; then
  echo "Uso: tools/test_reports_deletion.sh https://tu-app.onrender.com"
  exit 1
fi

THRESHOLD="${THRESHOLD:-3}"   # ej: THRESHOLD=3 tools/test_reports_deletion.sh "$BASE"
echo "BASE=${BASE} THRESHOLD=${THRESHOLD}"

note_txt="report test $(date +%s)-$RANDOM"
resp="$(curl -sS -X POST "$BASE/api/notes" -H 'Content-Type: application/json; charset=utf-8' --data "{\"text\":\"${note_txt}\"}")"
nid="$(printf '%s' "$resp" | sed -nE 's/.*"id":([0-9]+).*/\1/p')"
if [[ -z "${nid}" ]]; then
  echo "ERROR: no pude extraer id. resp=${resp}"
  exit 1
fi
echo "note id=${nid}"

post_report() {
  local url="$1"
  local mode="$2"  # json|form
  if [[ "${mode}" == "json" ]]; then
    curl -sS -o /dev/null -w '%{http_code}' -X POST "$url" \
      -H 'Content-Type: application/json; charset=utf-8' \
      --data '{"reason":"spam"}'
  else
    curl -sS -o /dev/null -w '%{http_code}' -X POST "$url" \
      -H 'Content-Type: application/x-www-form-urlencoded' \
      --data 'reason=spam'
  fi
}

report_once() {
  # 1) ruta base (singular)
  local code
  code="$(post_report "$BASE/api/notes/${nid}/report" json)"
  if [[ "$code" == "200" || "$code" == "201" || "$code" == "204" ]]; then
    echo "report JSON -> ${code}"
    return 0
  fi
  if [[ "$code" == "404" ]]; then
    # Probar FORM por si el backend espera form-urlencoded
    code="$(post_report "$BASE/api/notes/${nid}/report" form)"
    if [[ "$code" == "200" || "$code" == "201" || "$code" == "204" ]]; then
      echo "report FORM -> ${code}"
      return 0
    fi
    # 2) ruta alternativa (plural)
    code="$(post_report "$BASE/api/notes/${nid}/reports" json)"
    if [[ "$code" == "200" || "$code" == "201" || "$code" == "204" ]]; then
      echo "reports JSON -> ${code}"
      return 0
    fi
    code="$(post_report "$BASE/api/notes/${nid}/reports" form)"
    if [[ "$code" == "200" || "$code" == "201" || "$code" == "204" ]]; then
      echo "reports FORM -> ${code}"
      return 0
    fi
  fi
  echo "WARN: intento de report devolvió HTTP ${code}"
  return 1
}

for i in $(seq 1 "${THRESHOLD}"); do
  report_once || true
done

# Chequear que ya no exista
# pequeño delay por si hay lógica async
sleep 1
code="$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/api/notes/${nid}")"
if [[ "${code}" == "404" ]]; then
  echo "OK: nota ${nid} eliminada por umbral de reportes (>= ${THRESHOLD})."
  exit 0
else
  echo "FALLO: nota ${nid} aún existe (HTTP ${code}), el backend no eliminó tras ${THRESHOLD} reportes."
  exit 1
fi
