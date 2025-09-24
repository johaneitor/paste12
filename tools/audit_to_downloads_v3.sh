#!/usr/bin/env bash
set -euo pipefail

# Uso:
#   tools/audit_to_downloads_v3.sh https://host [TTL_CAP_ESPERADO]
# Ej:
#   tools/audit_to_downloads_v3.sh "https://paste12-rmsk.onrender.com" 2160

BASE="${1:?Uso: $0 https://host}"
TTL_EXPECTED="${2:-2160}"

DEST_DIR="${DEST_DIR:-$HOME/downloads}"
mkdir -p "$DEST_DIR" 2>/dev/null || true
TS="$(date -u +%Y%m%d-%H%M%SZ)"
OUT="$DEST_DIR/audit-${TS}.txt"

# Helpers de salida
ok(){ printf "✓ %s\n" "$*"; }
bad(){ printf "✗ %s\n" "$*"; }
hr(){ printf -- "---------------------------------------------\n"; }
jget(){ jq -r "$1" 2>/dev/null || echo ""; }
jitter(){ command -v usleep >/dev/null 2>&1 && usleep 40000 || sleep 0.04; }

# curl helpers: SIEMPRE devuelven código y guardan body/headers
curl_code_body(){
  local method="$1" url="$2" body_path="$3" hdr_path="${4:-}"
  if [ -n "${hdr_path:-}" ]; then
    curl -sS -X "$method" -D "$hdr_path" -o "$body_path" -w '%{http_code}' "$url"
  else
    curl -sS -X "$method"             -o "$body_path" -w '%{http_code}' "$url"
  fi
}

curl_json_code(){
  local method="$1" url="$2" body_path="$3" data="${4:-}"
  if [ -n "$data" ]; then
    printf '%s' "$data" \
    | curl -sS -X "$method" -H 'Accept: application/json' -H 'Content-Type: application/json' \
            --data-binary @- -o "$body_path" -w '%{http_code}' "$url"
  else
    curl -sS -X "$method" -H 'Accept: application/json' -H 'Content-Type: application/json' \
            -o "$body_path" -w '%{http_code}' "$url"
  fi
}

# Doble salida: pantalla + archivo
exec > >(tee -a "$OUT") 2>&1

echo "== HEALTH & DEPLOY =="
tmp_health_body="$(mktemp)"; tmp_health_hdr="$(mktemp)"
code="$(curl_code_body GET "$BASE/api/health" "$tmp_health_body" "$tmp_health_hdr")"
head -n1 "$tmp_health_hdr" || true
[ "$code" = "200" ] || bad "/api/health → $code"
DEPLOY_JSON="$(curl -sS "$BASE/api/deploy-stamp" || true)"
if [ -n "$DEPLOY_JSON" ]; then
  CMT="$(printf "%s" "$DEPLOY_JSON" | jget '.commit')"
  STP="$(printf "%s" "$DEPLOY_JSON" | jget '.stamp')"
  [ -n "$CMT" ] && ok "deploy-stamp commit: $CMT"
  [ -n "$STP" ] && ok "deploy-stamp fecha: $STP"
else
  echo "(aviso) deploy-stamp no disponible"
fi
hr

echo "== HEADERS / =="
tmp_root_hdr="$(mktemp)"
curl -sS -D "$tmp_root_hdr" -o /dev/null "$BASE/" >/dev/null 2>&1 || true
awk 'BEGIN{IGNORECASE=1}/^(HTTP\/|cache-control:|x-(index-source|wsgi-bridge):|x-max-ttl-hours:)/{print}' "$tmp_root_hdr"
hr

echo "== CREATE NOTE (JSON y FORM) =="
tmp_body="$(mktemp)"
code="$(curl_json_code POST "$BASE/api/notes" "$tmp_body" "$(jq -n --arg t "audit $(date -u +%Y-%m-%dT%H:%M:%SZ) texto largo para validar 1234567890 abcdefghij" '{text:$t}')" )"
JSON_ID="$(cat "$tmp_body" | jget '.item.id')"
[ "$code" = "201" ] && [ -n "$JSON_ID" ] && ok "JSON id: $JSON_ID" || bad "create JSON → $code body=$(cat "$tmp_body")"

tmp_body2="$(mktemp)"
code2="$(curl -sS -X POST -H 'Content-Type: application/x-www-form-urlencoded' \
         --data-urlencode "text=audit form $(date -u +%Y-%m-%dT%H:%M:%SZ) texto largo para validar 1234567890 abcdefghij" \
         -o "$tmp_body2" -w '%{http_code}' "$BASE/api/notes")"
FORM_ID="$(cat "$tmp_body2" | jget '.item.id')"
[ "$code2" = "201" ] && [ -n "$FORM_ID" ] && ok "FORM id: $FORM_ID" || bad "create FORM → $code2 body=$(cat "$tmp_body2")"

NEW="${JSON_ID:-$FORM_ID}"
PICK="${FORM_ID:-$JSON_ID}"
if [ -z "$NEW" ]; then
  bad "no hay nota creada; corto TTL/likes/paginación"
  echo "Archivo escrito en: $OUT"
  exit 1
fi
hr

echo "== TTL (GET /api/notes/:id) =="
tmp_get="$(mktemp)"
gcode="$(curl_code_body GET "$BASE/api/notes/$PICK" "$tmp_get")"
if [ "$gcode" = "200" ]; then
  TS="$(cat "$tmp_get" | jget '.item.timestamp')"
  EXP="$(cat "$tmp_get" | jget '.item.expires_at')"
  if [ -n "$TS" ] && [ -n "$EXP" ]; then
python - "$TS" "$EXP" "$TTL_EXPECTED" <<'PY'
import sys,datetime as dt
def p(s):
  try: return dt.datetime.fromisoformat(s.replace("Z","+00:00"))
  except: return dt.datetime.fromisoformat(s.split('.')[0])
t1,t2=p(sys.argv[1]),p(sys.argv[2])
ttl=(t2-t1).total_seconds()/3600
cap=float(sys.argv[3])
print(f"TTL medido: {ttl:.2f} h (cap esperado: {cap:.0f} h)")
print("OK: TTL ≤ cap" if ttl <= cap+0.1 else "ALERTA: TTL excede cap")
PY
  else
    echo "(aviso) faltan timestamp/expires_at en body:"
    cat "$tmp_get"
  fi
else
  bad "GET /api/notes/$PICK → $gcode"
  cat "$tmp_get"
fi
hr

echo "== LIKES (dedupe + FPs distintas + concurrencia) =="
# same-FP
tmp_like1="$(mktemp)"; l1c="$(curl_json_code POST "$BASE/api/notes/$NEW/like" "$tmp_like1")"
L1="$(cat "$tmp_like1" | jget '.likes')"; D1="$(cat "$tmp_like1" | jget '.deduped')"
tmp_like2="$(mktemp)"; l2c="$(curl_json_code POST "$BASE/api/notes/$NEW/like" "$tmp_like2")"
L2="$(cat "$tmp_like2" | jget '.likes')"; D2="$(cat "$tmp_like2" | jget '.deduped')"
echo "same-FP: ${L1:-?} ${D1:-?} -> ${L2:-?} ${D2:-?}"
if [ -n "${L1:-}" ] && { [ "$L1" = "$L2" ] || [ "${D2:-}" = "true" ]; }; then ok "dedupe OK"; else bad "dedupe anómalo"; fi

# FPs distintas (enviamos cabecera X-FP distinta)
tmp_a="$(mktemp)"; ka="$(curl -sS -X POST -H 'X-FP: A' -o "$tmp_a" -w '%{http_code}' "$BASE/api/notes/$NEW/like")"
A="$(cat "$tmp_a" | jget '.likes')"
tmp_b="$(mktemp)"; kb="$(curl -sS -X POST -H 'X-FP: B' -o "$tmp_b" -w '%{http_code}' "$BASE/api/notes/$NEW/like")"
B="$(cat "$tmp_b" | jget '.likes')"
tmp_c="$(mktemp)"; kc="$(curl -sS -X POST -H 'X-FP: C' -o "$tmp_c" -w '%{http_code}' "$BASE/api/notes/$NEW/like")"
C="$(cat "$tmp_c" | jget '.likes')"
echo "A/B/C (HTTP): $ka $kb $kc"
echo "A/B/C (likes): ${A:-?} -> ${B:-?} -> ${C:-?}"

# Concurrencia ligera (5 peticiones FP=Z)
tmp_before="$(mktemp)"; gb="$(curl_code_body GET "$BASE/api/notes/$NEW" "$tmp_before")"
BEFORE="$(cat "$tmp_before" | jget '.item.likes')"
tmp_codes="$(mktemp)"
for i in $(seq 1 5); do
  (curl -sS -o /dev/null -w '%{http_code}\n' -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: Z' >> "$tmp_codes") &
  jitter
done
wait || true
tmp_after="$(mktemp)"; ga="$(curl_code_body GET "$BASE/api/notes/$NEW" "$tmp_after")"
AFTER="$(cat "$tmp_after" | jget '.item.likes')"
if [ "$gb" = "200" ] && [ "$ga" = "200" ] && [[ "$BEFORE" =~ ^[0-9]+$ ]] && [[ "$AFTER" =~ ^[0-9]+$ ]]; then
  DELTA=$((AFTER-BEFORE))
  echo "concurrencia: antes=$BEFORE despues=$AFTER delta=$DELTA"
  echo "códigos: { $(sort "$tmp_codes" | uniq -c | sed 's/^ *//') }"
  [ "$DELTA" -le 1 ] && ok "concurrencia controlada (≤ +1)" || bad "concurrencia +$DELTA (>1)"
else
  echo "(aviso) no se pudo calcular delta likes: BEFORE='${BEFORE:-}' AFTER='${AFTER:-}' (GET codes: $gb/$ga)"
fi
hr

echo "== PAGINACIÓN (limit=5) =="
tmp_pg_body="$(mktemp)"; tmp_pg_hdr="$(mktemp)"
pg_code="$(curl_code_body GET "$BASE/api/notes?limit=5" "$tmp_pg_body" "$tmp_pg_hdr")"
echo "status: $pg_code"
if [ "$pg_code" = "200" ]; then
  LNK="$(awk 'BEGIN{IGNORECASE=1}/^link:/{print}' "$tmp_pg_hdr" | sed -n 's/.*<\([^>]*\)>\;\s*rel="next".*/\1/p')"
  XNC="$(awk 'BEGIN{IGNORECASE=1}/^x-next-cursor:/{sub(/^x-next-cursor:\s*/,"");print}' "$tmp_pg_hdr")"
  echo "Link next: ${LNK:-<none>}"
  echo "X-Next-Cursor: ${XNC:-<none>}"
  jq -r '.items[].id' "$tmp_pg_body" 2>/dev/null | sed 's/^/id: /' || cat "$tmp_pg_body"
else
  echo "(paginación no disponible: $pg_code)"
fi
hr

echo "== UI (index.html heurística) =="
tmp_html="$(mktemp)"; curl -sS -o "$tmp_html" "$BASE/" || true
grep -qi '<h1[^>]*class="[^"]*\bbrand\b' "$tmp_html" && echo "brand: OK" || echo "brand: (no detectado)"
ROT="$(grep -io '<h2[^>]*id="tagline-rot"[^>]*>' "$tmp_html" | wc -l | awk '{print $1}')"
FIXED="$(grep -io '<div[^>]*id="tagline"[^>]*>'         "$tmp_html" | wc -l | awk '{print $1}')"
echo "rotadores: $ROT ; taglines fijos: $FIXED"
hr

echo "Archivo escrito en: $OUT"
echo "(Termux: /data/data/com.termux/files/home/downloads/)"
