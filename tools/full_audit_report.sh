#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"
OUT="${2:-audit-$(date -u +%Y%m%d-%H%M%SZ).txt}"

jget(){ jq -r "$1" 2>/dev/null || echo ""; }
section(){ echo; echo "===== $* ====="; }
append(){ echo -e "$*" >> "$OUT"; }

: > "$OUT"

section "INFO" | tee -a "$OUT"
echo "Base: $BASE" | tee -a "$OUT"
date -u | sed 's/^/UTC: /' | tee -a "$OUT"

section "SALUD & DEPLOY" | tee -a "$OUT"
curl -sI "$BASE/api/health" | sed -n '1,20p' | sed 's/^/  /' | tee -a "$OUT"
DEPLOY="$(curl -fsS "$BASE/api/deploy-stamp" 2>/dev/null | jget '.commit')"
echo "deploy-stamp: ${DEPLOY:-<no expuesto>}" | tee -a "$OUT"

section "HEADERS /" | tee -a "$OUT"
curl -sI "$BASE/" | sed -n '1,50p' | sed 's/^/  /' | tee -a "$OUT"

section "UI: BRAND & TAGLINE & PREVIEW" | tee -a "$OUT"
HTML="$(curl -fsS "$BASE/")"
T1="$(echo "$HTML" | grep -ioc '<h1[^>]*class="[^"]*brand' || true)"
TR="$(echo "$HTML" | grep -ioc '<h2[^>]*id="tagline-rot"' || true)"
TF="$(echo "$HTML" | grep -ioc '<div[^>]*id="tagline"' || true)"
VM="$(echo "$HTML" | grep -ioc 'Ver más' || true)"
echo "h1.brand: $T1   tagline-rot: $TR   tagline (fijos): $TF   'Ver más': $VM" | tee -a "$OUT"

section "TTL (CAP anunciado y efectivo)" | tee -a "$OUT"
MAXH="$(curl -sI "$BASE/" | awk 'BEGIN{IGNORECASE=1}/^X-Max-TTL-Hours:/{print $2}' || true)"
echo "X-Max-TTL-Hours: ${MAXH:-<ausente>}" | tee -a "$OUT"
# Crear una nota por JSON (texto largo)
resp="$(jq -n --arg t "audit ttl $(date -u +%H:%M:%S) texto largo para validar" '{text:$t}' \
  | curl -sS -i -H 'Accept: application/json' -H 'Content-Type: application/json' --data-binary @- "$BASE/api/notes")"
code="$(printf "%s" "$resp" | sed -n '1{s/.* //;p;q}')"
body="$(printf "%s" "$resp" | awk 'BEGIN{p=0}/^\r?$/{p=1;next} p{print}')"
echo "POST /api/notes (JSON) => $code" | tee -a "$OUT"
nid="$(printf "%s" "$body" | jget '.item.id')"
if [ -n "$nid" ]; then
  full="$(curl -fsS "$BASE/api/notes/$nid")"
  ts="$(printf "%s" "$full" | jget '.item.timestamp')"
  exp="$(printf "%s" "$full" | jget '.item.expires_at')"
  ttlh="$(
python - "$ts" "$exp" <<'PY'
import sys,datetime as dt
def p(s):
  try: return dt.datetime.fromisoformat(s.replace("Z","+00:00"))
  except: return dt.datetime.fromisoformat(s.split('.')[0])
t1,t2=p(sys.argv[1]),p(sys.argv[2])
print(f"{(t2-t1).total_seconds()/3600:.2f}")
PY
)"
  echo "timestamp: $ts" | tee -a "$OUT"
  echo "expires  : $exp" | tee -a "$OUT"
  echo "TTL(h)   : $ttlh" | tee -a "$OUT"
else
  echo "no se pudo medir TTL (sin id)" | tee -a "$OUT"
fi

section "LIKES (dedupe y concurrencia corta)" | tee -a "$OUT"
NEW="$(jq -n --arg t "audit likes $(date -u +%H:%M:%S) nota larga de prueba para validar" '{text:$t}' \
  | curl -fsS -H 'Content-Type: application/json' --data-binary @- "$BASE/api/notes" | jget '.item.id')"
if [ -n "$NEW" ]; then
  a="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" | jq -r '.likes,.deduped' | paste -sd' ')"
  b="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" | jq -r '.likes,.deduped' | paste -sd' ')"
  echo "same-FP: $a -> $b" | tee -a "$OUT"
  curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: A' >/dev/null || true
  curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: B' >/dev/null || true
  curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: C' >/dev/null || true
  final="$(curl -fsS "$BASE/api/notes/$NEW" | jget '.item.likes')"
  echo "likes finales (esp 4): $final" | tee -a "$OUT"
  before="$final"
  for i in 1 2 3 4 5; do
    (curl -sS -o /dev/null -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: Z') &
  done
  wait
  after="$(curl -fsS "$BASE/api/notes/$NEW" | jget '.item.likes')"
  echo "race Z: antes=$before despues=$after delta=$((after-before))" | tee -a "$OUT"
else
  echo "no se pudo crear nota para likes" | tee -a "$OUT"
fi

section "PAGINACIÓN (page1, Link next, X-Next-Cursor)" | tee -a "$OUT"
resp="$(curl -fsS -i "$BASE/api/notes?limit=5")"
code="$(printf "%s" "$resp" | sed -n '1{s/.* //;p;q}')"
echo "GET page1 => $code" | tee -a "$OUT"
echo "$resp" | awk 'BEGIN{IGNORECASE=1}/^link:|^x-next-cursor:/{print}' | sed 's/^/  /' | tee -a "$OUT"
echo "$resp" | awk 'BEGIN{p=0}/^\r?$/{p=1;next} p{print}' | jq -r '.items[].id' 2>/dev/null \
  | sed 's/^/  id: /' | tee -a "$OUT"

section "FIN" | tee -a "$OUT"

# Copia a Download si existe
if [ -d "$HOME/storage/downloads" ]; then
  cp -f "$OUT" "$HOME/storage/downloads/$OUT" 2>/dev/null || true
  echo "Copia: $HOME/storage/downloads/$OUT" | tee -a "$OUT"
elif [ -d "/sdcard/Download" ]; then
  cp -f "$OUT" "/sdcard/Download/$OUT" 2>/dev/null || true
  echo "Copia: /sdcard/Download/$OUT" | tee -a "$OUT"
fi

echo "Reporte listo: $OUT"
