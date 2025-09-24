#!/usr/bin/env bash
set -euo pipefail

# Uso:
#   tools/audit_to_downloads_v1.sh https://host [TTL_CAP_ESPERADO]
# Ej:
#   tools/audit_to_downloads_v1.sh "https://paste12-rmsk.onrender.com" 2160

BASE="${1:?Uso: $0 https://host}"
TTL_EXPECTED="${2:-2160}"

# Salida en ~/downloads (Termux). Creamos si no existe.
DEST_DIR="${DEST_DIR:-$HOME/downloads}"
mkdir -p "$DEST_DIR" 2>/dev/null || true
TS="$(date -u +%Y%m%d-%H%M%SZ)"
OUT="$DEST_DIR/audit-${TS}.txt"

# Doble salida: en pantalla y archivo
exec > >(tee -a "$OUT") 2>&1

ok(){ printf "✓ %s\n" "$*"; }
bad(){ printf "✗ %s\n" "$*"; }
hr(){ printf -- "---------------------------------------------\n"; }
jget(){ jq -r "$1" 2>/dev/null || echo ""; }
body_from_http(){ awk 'BEGIN{p=0}/^\r?$/{p=1;next} p{print}'; }
code_from_http(){ sed -n '1{s/.* //;p;q}'; }
jitter(){ if command -v usleep >/dev/null 2>&1; then usleep 40000; else sleep 0.04; fi; }

echo "== HEALTH & DEPLOY =="
H="$(curl -sS -i "$BASE/api/health" || true)"; printf "%s\n" "$H" | sed -n '1p'
D="$(curl -sS "$BASE/api/deploy-stamp" 2>/dev/null || true)"
if [ -n "$D" ]; then
  CMT="$(printf "%s" "$D" | jget '.commit')"
  ST="$(printf "%s" "$D" | jget '.stamp')"
  [ -n "$CMT" ] && ok "deploy-stamp commit: $CMT" || echo "(aviso) deploy-stamp sin commit"
  [ -n "$ST" ] && ok "deploy-stamp fecha: $ST"
else
  echo "(aviso) deploy-stamp no disponible (404/500)"
fi
hr

echo "== HEADERS / =="
curl -sI "$BASE/" | awk 'BEGIN{IGNORECASE=1}/^(HTTP\/|cache-control:|x-(index-source|wsgi-bridge):|x-max-ttl-hours:)/{print}'
hr

echo "== CREATE NOTE (JSON y FORM) =="
JSON_ID="$(
  jq -n --arg t "audit $(date -u +%Y-%m-%dT%H:%M:%SZ) texto largo para validar 1234567890 abcdefghij" '{text:$t}' \
  | curl -fsS -H 'Content-Type: application/json' --data-binary @- "$BASE/api/notes" | jget '.item.id'
)"
[ -n "${JSON_ID:-}" ] && ok "JSON id: $JSON_ID" || bad "create JSON falló"

FORM_ID="$(
  curl -fsS -H 'Content-Type: application/x-www-form-urlencoded' \
       --data-urlencode "text=audit form $(date -u +%Y-%m-%dT%H:%M:%SZ) texto largo para validar 1234567890 abcdefghij" \
       "$BASE/api/notes" | jget '.item.id'
)"
[ -n "${FORM_ID:-}" ] && ok "FORM id: $FORM_ID" || bad "create FORM falló"

NEW="${JSON_ID:-$FORM_ID}"
if [ -z "$NEW" ]; then
  bad "no hay nota creada; abortando auditoría de TTL/likes/paginación"
  echo "Archivo escrito: $OUT"
  exit 1
fi
hr

echo "== TTL (GET /api/notes/:id) =="
try_ids=()
[ -n "${JSON_ID:-}" ] && try_ids+=("$JSON_ID")
[ -n "${FORM_ID:-}" ] && try_ids+=("$FORM_ID")
MEASURED=""

for ID in "${try_ids[@]}"; do
  BODY="$(curl -sS "$BASE/api/notes/$ID" || true)"
  OKFLG="$(printf "%s" "$BODY" | jget '.ok')"
  if [ "$OKFLG" = "true" ]; then
    TSJ="$(printf "%s" "$BODY" | jget '.item.timestamp')"
    EXPJ="$(printf "%s" "$BODY" | jget '.item.expires_at')"
    if [ -n "$TSJ" ] && [ -n "$EXPJ" ]; then
      echo "nota usada para TTL: $ID"
      python - "$TSJ" "$EXPJ" "$TTL_EXPECTED" <<'PY'
import sys,datetime as dt
def p(s):
  try: return dt.datetime.fromisoformat(s.replace("Z","+00:00"))
  except: return dt.datetime.fromisoformat(s.split('.')[0])
t1,t2=p(sys.argv[1]),p(sys.argv[2])
ttl=(t2-t1).total_seconds()/3600
print(f"TTL medido: {ttl:.2f} h (cap esperado: {sys.argv[3]} h)")
print("OK: TTL ≤ cap" if ttl <= float(sys.argv[3])+0.1 else "ALERTA: TTL excede cap")
PY
      MEASURED="1"
      break
    fi
  fi
done
[ -n "$MEASURED" ] || echo "(aviso) no se pudo medir TTL (GET devolvió error o faltan campos)"
hr

echo "== LIKES (dedupe + FPs distintas + concurrencia) =="
# same-FP
ONE="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" | jq -r '.likes,.deduped' | paste -sd' ' || true)"
TWO="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" | jq -r '.likes,.deduped' | paste -sd' ' || true)"
echo "same-FP: $ONE -> $TWO"
L1="$(echo "$ONE" | awk '{print $1}')"; L2="$(echo "$TWO" | awk '{print $1}')"; D2="$(echo "$TWO" | awk '{print $2}')"
if [ -n "$L1" ] && { [ "$L1" = "$L2" ] || [ "$D2" = "true" ]; }; then ok "dedupe OK"; else bad "dedupe falló"; fi

# FPs distintas
A="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: A' | jq -r '.likes' || true)"
B="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: B' | jq -r '.likes' || true)"
C="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: C' | jq -r '.likes' || true)"
echo "A/B/C => ${A:-<err>} -> ${B:-<err>} -> ${C:-<err>}"

# Concurrencia (ligera)
BEFORE="$(curl -fsS "$BASE/api/notes/$NEW" | jget '.item.likes' || true)"
TMP="$(mktemp -p "${TMPDIR:-.}" likes.codes.XXXX || mktemp likes.codes.XXXX)"
for i in $(seq 1 5); do
  (curl -sS -o /dev/null -w '%{http_code}\n' -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: Z' >> "$TMP") &
  jitter
done
wait || true
AFTER="$(curl -fsS "$BASE/api/notes/$NEW" | jget '.item.likes' || true)"
if [[ "$BEFORE" =~ ^[0-9]+$ ]] && [[ "$AFTER" =~ ^[0-9]+$ ]]; then
  DELTA=$((AFTER-BEFORE))
  echo "concurrencia: antes=$BEFORE despues=$AFTER delta=$DELTA"
  echo "códigos: { $(sort "$TMP" | uniq -c | sed 's/^ *//') }"
  [ "$DELTA" -le 1 ] && ok "concurrencia controlada (≤ +1)" || bad "concurrencia +$DELTA (>1)"
else
  echo "(aviso) no se pudo calcular delta likes: BEFORE='$BEFORE' AFTER='$AFTER'"
fi
rm -f "$TMP"
hr

echo "== PAGINACIÓN (limit=5) =="
PG="$(curl -fsS -i "$BASE/api/notes?limit=5" || true)"
PGCODE="$(printf "%s" "$PG" | code_from_http)"
echo "status: $PGCODE"
if [ "$PGCODE" = "200" ]; then
  LNK="$(printf "%s" "$PG" | awk 'BEGIN{IGNORECASE=1}/^link:/{print}' | sed -n 's/.*<\([^>]*\)>\;\s*rel="next".*/\1/p')"
  XNC="$(printf "%s" "$PG" | awk 'BEGIN{IGNORECASE=1}/^x-next-cursor:/{sub(/^x-next-cursor:\s*/,"");print}')"
  echo "Link next: ${LNK:-<none>}"
  echo "X-Next-Cursor: ${XNC:-<none>}"
  BODY="$(printf "%s" "$PG" | body_from_http)"
  echo "$BODY" | jq -r '.items[].id' 2>/dev/null | sed 's/^/id: /'
  if echo "$BODY" | grep -qiE 'UndefinedColumn|author_fp'; then
    echo "!! SCHEMA WARNING: Parece faltar una columna (p.ej. author_fp)."
    echo "   Soluciones: (A) ALTER TABLE note ADD COLUMN author_fp VARCHAR(128);"
    echo "               (B) o ajustar el SELECT para no requerirla."
  fi
else
  echo "(paginación no disponible: $PGCODE)"
fi
hr

echo "== UI (index.html heurística) =="
HTML="$(curl -fsS "$BASE/" || true)"
echo "$HTML" | grep -qi '<h1[^>]*class="[^"]*\bbrand\b' && echo "brand: OK" || echo "brand: (no detectado)"
ROT="$(echo "$HTML" | grep -io '<h2[^>]*id="tagline-rot"[^>]*>' | wc -l | awk '{print $1}')"
FIXED="$(echo "$HTML" | grep -io '<div[^>]*id="tagline"[^>]*>' | wc -l | awk '{print $1}')"
echo "rotadores: $ROT ; taglines fijos: $FIXED"
hr

echo "Archivo escrito en: $OUT"
echo "(En Termux puedes abrir/compartirlo desde /data/data/com.termux/files/home/downloads/)"
