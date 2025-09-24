#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
echo "== list_server_routes @ $BASE =="

# 1) Confirmar import sano (esperamos 404)
for i in $(seq 1 40); do
  c="$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/__api_import_error" || true)"
  [[ "$c" == "404" ]] && break
  sleep 2
done
echo "__api_import_error status: ${c:-000}"

# 2) Intentar _routes y fallback routes
R="$(curl -sS "$BASE/api/_routes" || true)"
if ! echo "$R" | python -m json.tool >/dev/null 2>&1; then
  echo "fallback /api/routes"
  R="$(curl -sS "$BASE/api/routes" || true)"
fi

if echo "$R" | python -m json.tool >/dev/null 2>&1; then
  echo "→ dump OK, primeras reglas:"
  echo "$R" | python - <<'PY'
import sys, json
j=json.load(sys.stdin)
routes = j.get("routes", [])
for r in routes[:50]:
    print(f"{r.get('rule'):35}  {','.join(r.get('methods',[]))}")
print("---")
has_ping = any(r.get("rule")=="/api/ping" for r in routes)
print(f"HAS /api/ping: {has_ping}")
PY
else
  echo "NO JSON en _routes/routes:"
  echo "$R" | head -c 400; echo
fi
