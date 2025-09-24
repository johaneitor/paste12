#!/usr/bin/env bash
set -euo pipefail

BASE="${1:-}"
if [[ -z "${BASE}" ]]; then
  echo "Uso: tools/test_cap_limit.sh https://tu-app.onrender.com"
  exit 1
fi

CAP="${CAP:-5}"   # ej: CAP=5 tools/test_cap_limit.sh "$BASE"
echo "BASE=${BASE} CAP=${CAP}"

first_id=""
for i in $(seq 1 $((CAP+1))); do
  txt="cap test $(date +%s)-$RANDOM"
  resp="$(curl -sS -X POST "$BASE/api/notes" -H 'Content-Type: application/json; charset=utf-8' --data "{\"text\":\"${txt}\"}")"
  nid="$(printf '%s' "$resp" | sed -nE 's/.*"id":([0-9]+).*/\1/p')"
  if [[ -z "${nid}" ]]; then
    echo "ERROR: no pude extraer id en iteración $i. resp=${resp}"
    exit 1
  fi
  echo " -> ${resp}"
  [[ -z "${first_id}" ]] && first_id="${nid}"
done

echo "Chequeando que la más antigua (${first_id}) haya sido podada…"
# Pequeño grace para poda async (si existiera)
sleep 1
code="$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/api/notes/${first_id}")"
if [[ "${code}" == "404" ]]; then
  echo "OK: cap aplicado (FIFO)."
  exit 0
else
  echo "FALLO: la nota más antigua (${first_id}) devolvió HTTP ${code} (esperado 404)."
  exit 1
fi
