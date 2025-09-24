#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"
TTL_EXPECTED="${2:-2160}"

ts="$(date -u +%Y%m%d-%H%M%SZ)"
OUT="audit-${ts}.txt"
exec > >(tee "$OUT") 2>&1

ok(){ echo "✓ $*"; }
bad(){ echo "✗ $*"; }

echo "== HEALTH & DEPLOY =="
curl -sI "$BASE/api/health" | sed -n '1p'
DEPLOY="$(curl -fsS "$BASE/api/deploy-stamp" 2>/dev/null | jq -r '.commit' 2>/dev/null || true)"
[ -n "$DEPLOY" ] && ok "deploy-stamp: $DEPLOY" || echo "(aviso) deploy-stamp no expuesto"
echo "---------------------------------------------"

echo "== HEADERS / =="
curl -sI "$BASE/" | awk 'BEGIN{IGNORECASE=1}/^(HTTP\/|cache-control:|x-(index-source|wsgi-bridge):)/{print}'
echo "---------------------------------------------"

echo "== CREATE NOTE (JSON y FORM) =="
JID="$(
  jq -n --arg t "audit json $(date -u +%H:%M:%SZ) texto largo 1234567890 abcdefghij" '{text:$t}' \
  | curl -fsS -H 'Content-Type: application/json' --data-binary @- "$BASE/api/notes" | jq -r '.item.id'
)"; echo "JSON id: ${JID:-<fail>}"
FID="$(
  curl -fsS -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode "text=audit form $(date -u +%H:%M:%SZ) texto largo 1234567890 abcdefghij" \
  "$BASE/api/notes" | jq -r '.item.id'
)"; echo "FORM id: ${FID:-<fail>}"
echo "---------------------------------------------"

echo "== LIKES (dedupe + shape) =="
NID="${JID:-$FID}"
if [ -n "${NID:-}" ]; then
  a="$(curl -fsS -X POST "$BASE/api/notes/$NID/like" | jq -r '.likes,.deduped' | paste -sd' ')"
  b="$(curl -fsS -X POST "$BASE/api/notes/$NID/like" | jq -r '.likes,.deduped' | paste -sd' ')"
  echo "same-FP: $a -> $b"
  curl -fsS -X POST "$BASE/api/notes/$NID/like" | jq -e '.ok,.id,.likes' >/dev/null 2>&1 && ok "JSON ok/id/likes" || bad "JSON inválido"
else
  bad "no se pudo crear nota para likes"
fi
echo "---------------------------------------------"

echo "== TTL (medición) =="
if [ -n "${JID:-}" ]; then
  full="$(curl -fsS "$BASE/api/notes/$JID")"
  ts="$(printf "%s" "$full" | jq -r '.item.timestamp')"
  exp="$(printf "%s" "$full" | jq -r '.item.expires_at')"
  if [ -n "$ts" ] && [ -n "$exp" ]; then
python - "$ts" "$exp" "$TTL_EXPECTED" <<'PY'
import sys,datetime as dt
def p(s):
  try: return dt.datetime.fromisoformat(s.replace("Z","+00:00"))
  except: return dt.datetime.fromisoformat(s.split('.')[0])
t1,t2=p(sys.argv[1]),p(sys.argv[2])
ttl=(t2-t1).total_seconds()/3600
print(f"TTL medido: {ttl:.2f} h (cap esperado ≤ {sys.argv[3]} h)")
PY
  else
    bad "no pude leer timestamp/expires_at"
  fi
else
  echo "(salteado) sin id para TTL"
fi
echo "---------------------------------------------"

echo "== PAGINACIÓN (limit=5, hasta 3 páginas) =="
resp="$(curl -fsS -i "$BASE/api/notes?limit=5")"
code="$(printf "%s" "$resp" | sed -n '1{s/.* //;p;q}')"
echo "page1 code: $code"
body="$(printf "%s" "$resp" | awk 'BEGIN{p=0}/^\r?$/{p=1;next} p{print}')"
ids="$(printf "%s" "$body" | jq -r '.items[].id' 2>/dev/null || true)"
echo "page1 ids: $(echo "$ids" | tr '\n' ' ')"
link_next="$(printf "%s" "$resp" | awk 'BEGIN{IGNORECASE=1}/^link:/{print}' | sed -n 's/.*<\([^>]*\)>\;\s*rel="next".*/\1/p')"
[ -n "$link_next" ] && ok "Link: next presente" || echo "(aviso) Link next ausente"

if [ -n "$link_next" ]; then
  [[ "$link_next" =~ ^/ ]] && next_url="$BASE$link_next" || next_url="$link_next"
  for p in 2 3; do
    echo "-- page $p --"
    r2="$(curl -fsS -i "$next_url")"
    code2="$(printf "%s" "$r2" | sed -n '1{s/.* //;p;q}')"
    b2="$(printf "%s" "$r2" | awk 'BEGIN{p=0}/^\r?$/{p=1;next} p{print}')"
    echo "code: $code2"
    ids2="$(printf "%s" "$b2" | jq -r '.items[].id' 2>/dev/null || true)"
    echo "ids: $(echo "$ids2" | tr '\n' ' ')"
    link_next="$(printf "%s" "$r2" | awk 'BEGIN{IGNORECASE=1}/^link:/{print}' | sed -n 's/.*<\([^>]*\)>\;\s*rel="next".*/\1/p')"
    [ -n "$link_next" ] || { echo "(fin) sin next"; break; }
    [[ "$link_next" =~ ^/ ]] && next_url="$BASE$link_next" || next_url="$link_next"
  done
fi
echo "---------------------------------------------"

echo "Archivo: $OUT"
