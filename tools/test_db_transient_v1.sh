#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"

ok(){ printf "OK  - %s\n" "$*"; }
ko(){ printf "FAIL- %s\n" "$*"; exit 1; }

# 1) tomar un id real
J="$(curl -fsS "$BASE/api/notes?limit=1")"
ID="$(python - <<'PY'
import sys, json
a=json.loads(sys.stdin.read() or "[]")
print(a[0]["id"] if a else "")
PY
<<<"$J")"
[[ -n "${ID:-}" ]] || ko "no se pudo resolver un id de nota"

# 2) lecturas repetidas
fails=0
for i in $(seq 1 20); do
  code="$(curl -fsS -o /dev/null -w '%{http_code}' "$BASE/api/notes?limit=10")" || code="000"
  [[ "$code" == "200" ]] || fails=$((fails+1))
done
[[ $fails -eq 0 ]] && ok "20x GET /api/notes sin 500" || ko "GET /api/notes tuvo $fails fallos"

# 3) likes repetidos (sobre el mismo id; el backend debe tolerarlo)
fails=0
for i in $(seq 1 20); do
  code="$(curl -fsS -o /dev/null -w '%{http_code}' -X POST "$BASE/api/notes/$ID/like")" || code="000"
  [[ "$code" =~ ^(200|201|204)$ ]] || fails=$((fails+1))
done
[[ $fails -eq 0 ]] && ok "20x POST like sin 500" || ko "POST like tuvo $fails fallos"

echo "RESUMEN: PASS ✅ (anti-500)"
