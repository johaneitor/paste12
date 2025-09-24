#!/usr/bin/env bash
set -euo pipefail

BASE="${1:?Uso: $0 https://host}"
TTL_EXPECTED="${2:-2160}"   # horas (cap de 3 meses, si aplica)
PAR_CONC="${PAR_CONC:-5}"   # concurrencia para likes (baja para no estresar)

ok(){ printf "✓ %s\n" "$*"; }
bad(){ printf "✗ %s\n" "$*"; }
hr(){ printf -- "---------------------------------------------\n"; }
jget(){ jq -r "$1" 2>/dev/null || echo ""; }
body_from_http(){ awk 'BEGIN{p=0}/^\r?$/{p=1;next} p{print}'; }
code_from_http(){ sed -n '1{s/.* //;p;q}'; }

echo "== HEALTH & HEADERS =="
curl -sI "$BASE/api/health" | sed -n '1p'
curl -sI "$BASE/" | awk 'BEGIN{IGNORECASE=1}/^(HTTP\/|cache-control:|x-(index-source|wsgi-bridge):)/{print}'
hr

echo "== CREATE NOTE (JSON y FORM) =="
# JSON (texto largo para pasar validación)
JSON_ID="$(
  jq -n --arg t "smoke $(date -u +%H:%M:%SZ) texto largo para validar 1234567890 abcdefghij" '{text:$t}' \
  | curl -fsS -H 'Content-Type: application/json' --data-binary @- "$BASE/api/notes" \
  | jget '.item.id'
)"
if [ -n "$JSON_ID" ] && [[ "$JSON_ID" =~ ^[0-9]+$ ]]; then ok "JSON id: $JSON_ID"; else bad "create JSON falló"; fi

# FORM como variante
FORM_ID="$(
  curl -fsS -H 'Content-Type: application/x-www-form-urlencoded' \
       --data-urlencode "text=smoke form $(date -u +%H:%M:%SZ) texto largo para validar 1234567890 abcdefghij" \
       "$BASE/api/notes" | jget '.item.id'
)"
if [ -n "$FORM_ID" ] && [[ "$FORM_ID" =~ ^[0-9]+$ ]]; then ok "FORM id: $FORM_ID"; else bad "create FORM falló"; fi
NEW="${JSON_ID:-$FORM_ID}"
[ -n "$NEW" ] || { bad "no hay nota creada para continuar"; exit 1; }
hr

echo "== TTL (GET /api/notes/:id) =="
TTL_CODE="$(curl -sS -i "$BASE/api/notes/$NEW" | tee /tmp/_get_one.http | code_from_http || true)"
if [ "$TTL_CODE" = "200" ]; then
  TS="$(cat /tmp/_get_one.http | body_from_http | jget '.item.timestamp')"
  EXP="$(cat /tmp/_get_one.http | body_from_http | jget '.item.expires_at')"
  if [ -n "$TS" ] && [ -n "$EXP" ]; then
    python - "$TS" "$EXP" "$TTL_EXPECTED" <<'PY'
import sys,datetime as dt
def p(s):
  try: return dt.datetime.fromisoformat(s.replace("Z","+00:00"))
  except: return dt.datetime.fromisoformat(s.split('.')[0])
t1,t2=p(sys.argv[1]),p(sys.argv[2])
ttl=(t2-t1).total_seconds()/3600
print(f"· TTL medido: {ttl:.2f} h")
if ttl <= float(sys.argv[3])+0.1:
  print("✓ TTL ≤ cap esperado")
else:
  print("✗ TTL excede el cap esperado")
PY
  else
    bad "no se pudo leer timestamp/expires_at"
  fi
else
  bad "GET /api/notes/$NEW → $TTL_CODE (no se pudo medir TTL)"
fi
hr

echo "== LIKES (dedupe, FPs distintas y concurrencia) =="
ONE="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" | jq -r '.likes,.deduped' | paste -sd' ' || true)"
TWO="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" | jq -r '.likes,.deduped' | paste -sd' ' || true)"
echo "· same-FP => $ONE -> $TWO"
L1="$(echo "$ONE" | awk '{print $1}')"; L2="$(echo "$TWO" | awk '{print $1}')"; D2="$(echo "$TWO" | awk '{print $2}')"
if [ "$L1" = "$L2" ] || [ "$D2" = "true" ]; then ok "dedupe OK"; else bad "dedupe falló"; fi

A="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: A' | jq -r '.likes' || true)"
B="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: B' | jq -r '.likes' || true)"
C="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: C' | jq -r '.likes' || true)"
echo "· A/B/C => $A -> $B -> $C"

BEFORE="$(curl -fsS "$BASE/api/notes/$NEW" | jq -r '.item.likes')"
TMP="$(mktemp)"
for i in $(seq 1 "$PAR_CONC"); do
  (curl -sS -o /dev/null -w '%{http_code}\n' -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: Z' >> "$TMP") &
  usleep 40000 2>/dev/null || sleep 0.04
done
wait
AFTER="$(curl -fsS "$BASE/api/notes/$NEW" | jq -r '.item.likes')"
DELTA=$((AFTER-BEFORE))
DIST="$(sort "$TMP" | uniq -c | sed 's/^ *//')"; rm -f "$TMP"
echo "· antes=$BEFORE  despues=$AFTER  delta=$DELTA"
echo "· códigos concurrencia: { $DIST }"
[ "$DELTA" -le 1 ] && ok "concurrencia controlada (≤ +1)" || bad "concurrencia incrementó +$DELTA (>1)"
hr

echo "== PAGINACIÓN mínima (limit=5) =="
PG="$(curl -fsS -i "$BASE/api/notes?limit=5")" || true
PGCODE="$(printf "%s" "$PG" | code_from_http)"
echo "· status: $PGCODE"
if [ "$PGCODE" = "200" ]; then
  NEXT="$(printf "%s" "$PG" | awk 'BEGIN{IGNORECASE=1}/^link:/{print}' | sed -n 's/.*<\([^>]*\)>\;\s*rel="next".*/\1/p')"
  XCUR="$(printf "%s" "$PG" | awk 'BEGIN{IGNORECASE=1}/^x-next-cursor:/{sub(/^x-next-cursor:\s*/,"");print}')"
  [ -n "$NEXT" ] && ok "Link: next presente" || echo "(aviso) Link next ausente"
  [ -n "$XCUR" ] && ok "X-Next-Cursor presente" || echo "(aviso) X-Next-Cursor ausente"
  BODY="$(printf "%s" "$PG" | body_from_http)"
  IDS="$(printf "%s" "$BODY" | jq -r '.items[].id' 2>/dev/null || true)"
  CNT="$(printf "%s" "$IDS" | grep -c . || true)"
  [ "$CNT" -gt 0 ] && ok "items page1: $CNT" || bad "page1 vacía"
  # Detectar error de schema típico (columna faltante)
  if echo "$BODY" | grep -qiE 'UndefinedColumn|author_fp'; then
    bad "posible mismatch de schema (p.ej. author_fp ausente). Requiere migración o ajustar SELECT."
  fi
else
  bad "GET /api/notes?limit=5 → $PGCODE"
fi
hr

echo "== UI (index.html heurística) =="
HTML="$(curl -fsS "$BASE/")"
echo "$HTML" | grep -qi '<h1[^>]*class="[^"]*\bbrand\b' && ok "h1.brand presente" || echo "(aviso) h1.brand no detectado"
ROT="$(echo "$HTML" | grep -io '<h2[^>]*id="tagline-rot"[^>]*>' | wc -l | awk '{print $1}')"
FIXED="$(echo "$HTML" | grep -io '<div[^>]*id="tagline"[^>]*>' | wc -l | awk '{print $1}')"
[ "$ROT" = "1" ] && ok "tagline rotador: 1" || echo "(aviso) rotadores=$ROT"
[ "$FIXED" = "0" ] && ok "tagline fijo: 0" || echo "(aviso) taglines fijos=$FIXED"

echo "== FIN SMOKE =="
