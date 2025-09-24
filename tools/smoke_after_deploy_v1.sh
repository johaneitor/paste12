#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: smoke_after_deploy_v1.sh BASE_URL}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
OUT="/sdcard/Download/smoke-$TS.txt"

echo "== Smoke $TS ==" | tee "$OUT"
echo "BASE: $BASE"      | tee -a "$OUT"

# Esperar health 200
ok=0
for i in $(seq 1 40); do
  code="$(curl -fsS -o /dev/null -w '%{http_code}' "$BASE/api/health" || true)"
  echo "health try $i -> $code" | tee -a "$OUT"
  if [[ "$code" == "200" ]]; then ok=1; break; fi
  sleep 3
done
[[ $ok -eq 1 ]] || { echo "FAIL health" | tee -a "$OUT"; exit 2; }
curl -fsS "$BASE/api/health" | tee -a "$OUT"

echo -e "\n-- /api/notes --" | tee -a "$OUT"
curl -fsS -D "/sdcard/Download/api-notes-h-$TS.txt" "$BASE/api/notes?limit=10" -o "/sdcard/Download/api-notes-$TS.json" || true
sed -n '1,40p' "/sdcard/Download/api-notes-h-$TS.txt" | tee -a "$OUT"
echo "Guardados: api-notes-*.json/txt en /sdcard/Download" | tee -a "$OUT"

echo -e "\n-- OPTIONS /api/notes --" | tee -a "$OUT"
curl -fsS -X OPTIONS -D - "$BASE/api/notes" -o /dev/null | sed -n '1,40p' | tee -a "$OUT"

echo -e "\nOK. Reporte: $OUT"
