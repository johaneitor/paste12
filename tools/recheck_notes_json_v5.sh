#!/usr/bin/env bash
set -Eeuo pipefail

BASE="${1:-http://127.0.0.1:8000}"
LIMIT="${2:-2}"

echo "➤ Esperando health 200 en $BASE…"
for i in {1..30}; do
  code="$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/api/health" || true)"
  if [ "$code" = "200" ]; then echo "OK health=200"; break; fi
  sleep 1
done

echo "➤ Inyecto 3 notas dummy para asegurar 2+ páginas"
for i in 1 2 3; do
  curl -sS -H 'Content-Type: application/json' \
       -d '{"text":"recheck v5","hours":24}' \
       "$BASE/api/notes" >/dev/null || true
done

H1="$(mktemp)"; B1="$(mktemp)"
curl -sS -D "$H1" -o "$B1" "$BASE/api/notes?limit=$LIMIT" >/dev/null

echo
echo "— STATUS & HEADERS (página 1) —"
cat "$H1"
echo
echo "— len(JSON página 1) —"
python - "$B1" <<'PY'
import sys, json, io
with io.open(sys.argv[1], "r", encoding="utf-8") as f:
    data = json.load(f)
print(len(data))
PY

# Extraer cursor con limpieza (solo dígitos)
NEXT="$(awk -F': ' 'tolower($1)=="x-next-after"{print $2}' "$H1" | tr -d '\r\n' | sed -E 's/[^0-9].*$//')"
if [ -n "${NEXT:-}" ]; then
  echo "X-Next-After: $NEXT"
  H2="$(mktemp)"; B2="$(mktemp)"
  curl -sS -D "$H2" -o "$B2" "$BASE/api/notes?limit=$LIMIT&after_id=$NEXT" >/dev/null
  echo
  echo "— STATUS & HEADERS (página 2) —"
  cat "$H2"
  echo
  echo "— len(JSON página 2) —"
  python - "$B2" <<'PY'
import sys, json, io
with io.open(sys.argv[1], "r", encoding="utf-8") as f:
    data = json.load(f)
print(len(data))
PY
else
  echo "No hay X-Next-After (no hay más páginas)."
fi
