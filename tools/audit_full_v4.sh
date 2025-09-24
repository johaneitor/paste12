#!/usr/bin/env bash
set -euo pipefail

BASE="${1:?Uso: $0 https://host}"
TTL_EXPECTED="${2:-2160}"

TS="$(date -u +%Y%m%d-%H%M%SZ)"
OUT="audit-${TS}.txt"
exec > >(tee -a "$OUT") 2>&1

ok(){ printf "✓ %s\n" "$*"; }
bad(){ printf "✗ %s\n" "$*"; }
hr(){ printf -- "---------------------------------------------\n"; }
jget(){ jq -r "$1" 2>/dev/null || echo ""; }
body_from_http(){ awk 'BEGIN{p=0}/^\r?$/{p=1;next} p{print}'; }
code_from_http(){ sed -n '1{s/.* //;p;q}'; }

echo "== HEALTH & DEPLOY =="
H="$(curl -sS -i "$BASE/api/health")"; printf "%s\n" "$H" | sed -n '1p'
D="$(curl -sS "$BASE/api/deploy-stamp" 2>/dev/null || true)"
if [ -n "$D" ]; then
  CMT="$(printf "%s" "$D" | jget '.commit')"; ST="$(printf "%s" "$D" | jget '.stamp')"
  [ -n "$CMT" ] && ok "deploy-stamp commit: $CMT" || echo "(aviso) deploy-stamp sin commit"
  [ -n "$ST" ] && ok "deploy-stamp fecha: $ST"
else
  echo "(aviso) deploy-stamp no disponible (404/500)"
fi
hr

echo "== HEADERS ROOT =="
curl -sI "$BASE/" | awk 'BEGIN{IGNORECASE=1}/^(HTTP\/|cache-control:|x-(index-source|wsgi-bridge):|x-max-ttl-hours:)/{print}'
hr

echo "== CREATE NOTE (JSON y FORM) =="
JSON_ID="$(
  jq -n --arg t "audit $(date -u +%Y-%m-%dT%H:%M:%SZ) texto largo para validar 1234567890 abcdefghij" '{text:$t}' \
  | curl -fsS -H 'Content-Type: application/json' --data-binary @- "$BASE/api/notes" | jget '.item.id'
)"
echo "JSON id: ${JSON_ID:-<fail>}"
FORM_ID="$(
  curl -fsS -H 'Content-Type: application/x-www-form-urlencoded' \
       --data-urlencode "text=audit form $(date -u +%Y-%m-%dT%H:%M:%SZ) texto largo para validar 1234567890 abcdefghij" \
       "$BASE/api/notes" | jget '.item.id'
)"
echo "FORM id: ${FORM_ID:-<fail>}"
NEW="${JSON_ID:-$FORM_ID}"
[ -n "$NEW" ] || { bad "no se pudo crear nota"; echo "Archivo: $OUT"; exit 1; }
hr

echo "== TTL (GET /api/notes/:id) =="
TTL_HTTP="$(curl -sS -i "$BASE/api/notes/$NEW")"
TTL_CODE="$(printf "%s" "$TTL_HTTP" | code_from_http)"
echo "status: $TTL_CODE"
if [ "$TTL_CODE" = "200" ]; then
  TS="$(printf "%s" "$TTL_HTTP" | body_from_http | jget '.item.timestamp')"
  EXP="$(printf "%s" "$TTL_HTTP" | body_from_http | jget '.item.expires_at')"
  if [ -n "$TS" ] && [ -n "$EXP" ]; then
python - "$TS" "$EXP" "$TTL_EXPECTED" <<'PY'
import sys,datetime as dt
def p(s):
  try: return dt.datetime.fromisoformat(s.replace("Z","+00:00"))
  except: return dt.datetime.fromisoformat(s.split('.')[0])
t1,t2=p(sys.argv[1]),p(sys.argv[2])
ttl=(t2-t1).total_seconds()/3600
print(f"TTL medido: {ttl:.2f} h")
print("CAP esperado:", sys.argv[3], "h")
print("OK" if ttl <= float(sys.argv[3])+0.1 else "EXCEDE CAP")
PY
  else
    bad "faltan campos timestamp/expires_at"
  fi
else
  bad "GET /api/notes/$NEW → $TTL_CODE (posible 404 si handler no montado)"
fi
hr

echo "== LIKES (dedupe + distinta FP + concurrencia) =="
ONE="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" | jq -r '.likes,.deduped' | paste -sd' ' || true)"
TWO="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" | jq -r '.likes,.deduped' | paste -sd' ' || true)"
echo "same-FP: $ONE -> $TWO"
echo "$TWO" | jq -R 'split(" ")|{likes:.[0],deduped:.[1]}' 2>/dev/null || true
A="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: A' | jq -r '.likes' || true)"
B="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: B' | jq -r '.likes' || true)"
C="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: C' | jq -r '.likes' || true)"
echo "A/B/C => $A -> $B -> $C"
BEFORE="$(curl -fsS "$BASE/api/notes/$NEW" | jget '.item.likes')"
TMP="$(mktemp)"
for i in $(seq 1 5); do
  (curl -sS -o /dev/null -w '%{http_code}\n' -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: Z' >> "$TMP") &
  usleep 40000 2>/dev/null || sleep 0.04
done
wait
AFTER="$(curl -fsS "$BASE/api/notes/$NEW" | jget '.item.likes')"
DELTA=$((AFTER-BEFORE))
echo "concurrencia: antes=$BEFORE despues=$AFTER delta=$DELTA"
echo "códigos: { $(sort "$TMP" | uniq -c | sed 's/^ *//') }"
rm -f "$TMP"
hr

echo "== PAGINACIÓN (limit=5, una vuelta) =="
PAGE="$(curl -sS -i "$BASE/api/notes?limit=5" || true)"
PGCODE="$(printf "%s" "$PAGE" | code_from_http)"
echo "status: $PGCODE"
if [ "$PGCODE" = "200" ]; then
  LNK="$(printf "%s" "$PAGE" | awk 'BEGIN{IGNORECASE=1}/^link:/{print}' | sed -n 's/.*<\([^>]*\)>\;\s*rel="next".*/\1/p')"
  XNC="$(printf "%s" "$PAGE" | awk 'BEGIN{IGNORECASE=1}/^x-next-cursor:/{sub(/^x-next-cursor:\s*/,"");print}')"
  echo "Link next: ${LNK:-<none>}"
  echo "X-Next-Cursor: ${XNC:-<none>}"
  BODY="$(printf "%s" "$PAGE" | body_from_http)"
  echo "$BODY" | jq -r '.items[].id' 2>/dev/null | head -n5 | sed 's/^/id: /'
  # Heurística de error de schema
  if echo "$BODY" | grep -qiE 'UndefinedColumn|author_fp'; then
    echo "!! SCHEMA WARNING: Parece faltar una columna (p.ej. author_fp)."
    echo "   Opciones: (A) agregar columna: ALTER TABLE note ADD COLUMN author_fp VARCHAR(128);"
    echo "             (B) o ajustar el SELECT en el backend para no requerirla."
  fi
else
  echo "(paginación no disponible: $PGCODE)"
fi
hr

echo "== UI checks (index.html) =="
HTML="$(curl -fsS "$BASE/" || true)"
echo "$HTML" | grep -qi '<h1[^>]*class="[^"]*\bbrand\b' && echo "brand: OK" || echo "brand: (no detectado)"
ROT="$(echo "$HTML" | grep -io '<h2[^>]*id="tagline-rot"[^>]*>' | wc -l | awk '{print $1}')"
FIXED="$(echo "$HTML" | grep -io '<div[^>]*id="tagline"[^>]*>' | wc -l | awk '{print $1}')"
echo "rotadores: $ROT ; taglines fijos: $FIXED"
hr

echo "Archivo escrito: $OUT"
echo "Sugerencia Termux: termux-share -a send -c text/plain $OUT  # o cp a ~/downloads/"
