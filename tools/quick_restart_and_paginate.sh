#!/usr/bin/env bash
set -Eeuo pipefail

BASE="${1:-http://127.0.0.1:8000}"
LIMIT="${2:-2}"
SEED="${3:-3}"

LOG="${TMPDIR:-/data/data/com.termux/files/usr/tmp}/paste12_server.log"
mkdir -p "$(dirname "$LOG")"

echo "➤ Kill & clean (puertos/servicios antiguos)"
pkill -9 -f "python .*run\.py" 2>/dev/null || true
pkill -9 -f gunicorn          2>/dev/null || true
pkill -9 -f waitress          2>/dev/null || true
pkill -9 -f flask             2>/dev/null || true
fuser -k 8000/tcp 2>/dev/null || true
lsof -ti:8000 2>/dev/null | xargs -r kill -9 || true

echo "➤ Start"
nohup python run.py >"$LOG" 2>&1 & disown || true
sleep 2

echo "➤ Esperando health 200 en $BASE…"
for i in {1..30}; do
  code="$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/api/health" || true)"
  [ "$code" = "200" ] && { echo "OK health=200"; break; }
  sleep 1
done

echo "➤ Inyecto $SEED notas dummy para asegurar 2+ páginas"
for i in $(seq 1 "$SEED"); do
  curl -sS -H 'Content-Type: application/json' -d '{"text":"quick-check","hours":24}' "$BASE/api/notes" >/dev/null || true
done

page_fetch() {
  local url="$1"
  local H="$(mktemp)" B="$(mktemp)"
  curl -sS -D "$H" -o "$B" "$url" >/dev/null
  local ctype
  ctype="$(sed -n '1,/^$/p' "$H" | awk -F': ' 'tolower($1)=="content-type"{print tolower($2)}')"
  echo
  echo "— STATUS & HEADERS —"
  tr -d '\r' < "$H" | sed -n '1,/^$/p'
  echo
  echo "— BODY (primeras 800 chars) —"
  head -c 800 "$B"; echo
  if echo "$ctype" | grep -q 'application/json'; then
    python - <<PY
import io,json
with io.open("$B","r",encoding="utf-8") as f:
    data=json.load(f)
print("OK JSON · len =", len(data))
if data:
    ids=[d.get("id") for d in data]
    print("IDs:", ids[0], "…", ids[-1])
PY
  else
    echo "Content-Type no JSON: $ctype"
  fi
  awk -F': ' 'tolower($1)=="x-next-after"{print $2}' "$H" | tr -d '\r\n'
}

echo "➤ Página 1 (limit=$LIMIT)"
NEXT="$(page_fetch "$BASE/api/notes?limit=$LIMIT" | tail -n1)"
if [ -n "${NEXT:-}" ]; then
  echo "X-Next-After: $NEXT"
fi

# Iterar páginas siguientes si hay cursor
while [ -n "${NEXT:-}" ]; do
  echo "➤ Siguiente página (after_id=$NEXT)"
  NEXT="$(page_fetch "$BASE/api/notes?limit=$LIMIT&after_id=$NEXT" | tail -n1)"
  [ -n "${NEXT:-}" ] && echo "X-Next-After: $NEXT"
done

echo
echo "✓ Listo. Log: $LOG"
