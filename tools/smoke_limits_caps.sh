#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; CAP_HOURS="${2:-2160}"; MAX_LIMIT="${3:-100}"
[ -n "$BASE" ] || { echo "uso: $0 https://host [ttl_cap_horas=2160] [max_limit=100]"; exit 2; }

ORIG='https://example.com'

echo "== HEALTH =="
curl -sS -i "$BASE/api/health" | sed -n '1,40p'; echo

echo "== PRELIGHT (OPTIONS) =="
curl -sS -i -X OPTIONS "$BASE/api/notes" \
  -H "Origin: $ORIG" \
  -H 'Access-Control-Request-Method: POST' | sed -n '1,80p'; echo

echo "== CREATE (con Origin; espera ACAO) =="
ID="$(
  printf '{"text":"limits %s abcdefghij"}' "$(date -u +%H:%M:%SZ)" |
  curl -fsS -i -H "Origin: $ORIG" -H 'Content-Type: application/json' --data-binary @- "$BASE/api/notes" |
  tee /dev/stderr | sed -n 's/.*\r$//;/^{/,$p' | { command -v jq >/dev/null && jq -r '.item.id // .id // empty' || cat; }
)"
echo "id=$ID"; echo

if [ -n "$ID" ]; then
  echo "== TTL (GET /api/notes/:id) =="
  TMP="$(mktemp)"; curl -sS -D "$TMP.h" "$BASE/api/notes/$ID" -o "$TMP.b" >/dev/null || true
  head -n1 "$TMP.h"
  CC="$(grep -i '^Cache-Control:' "$TMP.h" | head -n1 | cut -d' ' -f2-)"
  if echo "$CC" | grep -qi 'max-age'; then
    MA="$(echo "$CC" | sed -n 's/.*max-age=\([0-9]\+\).*/\1/p')"
    if [ -n "$MA" ]; then
      H=$(( MA / 3600 ))
      echo "TTL medido: ${H}.00 h (cap esperado: ${CAP_HOURS} h)"
      if [ "$H" -le "$CAP_HOURS" ]; then echo "OK: TTL ≤ cap"; else echo "⚠ TTL > cap"; fi
    fi
  else
    echo "⚠ sin Cache-Control max-age"
  fi
fi
echo

echo "== PAGINACIÓN (limit muy grande; el servidor debe capear) =="
curl -sS "$BASE/api/notes?limit=$((MAX_LIMIT*50))" -D - -o - | {
  # extrae cabecera Link y X-Next-Cursor, y cuenta items
  awk '
    BEGIN{hdr=1; body=""; print_status=1}
    hdr && NF==0 {hdr=0; next}
    hdr { if ($1=="Link:" || $1=="X-Next-Cursor:" || $1 ~ /^HTTP\//) print; next }
    { body=body $0 "\n" }
    END{
      print "----"
      print body | "jq -r \".items|length\" 2>/dev/null"; close("jq -r \".items|length\" 2>/dev/null")
    }'
} | tee /dev/stderr | {
  LEN=$(tail -n1 | tr -d '\r\n')
  echo "items devueltos: $LEN"
  if [ -n "$LEN" ] && [ "$LEN" -le "$MAX_LIMIT" ]; then
    echo "OK: cap de 'limit' ≤ $MAX_LIMIT"
  else
    echo "⚠ 'limit' no capeado (esperado ≤ $MAX_LIMIT)"
  fi
}
echo

echo "== CORS real en like (ACAO/Vary esperados) =="
curl -sS -i -H "Origin: $ORIG" -X POST "$BASE/api/notes/${ID}/like" | sed -n '1,40p'
