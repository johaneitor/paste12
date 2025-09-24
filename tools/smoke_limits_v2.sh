#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"
TTL_EXPECTED="${2:-2160}"

pass=0; fail=0
ok(){ echo "✓ $*"; pass=$((pass+1)); }
bad(){ echo "✗ $*"; fail=$((fail+1)); }
hr(){ printf -- "---------------------------------------------\n"; }

# helpers
jget(){ jq -r "$1" 2>/dev/null || echo ""; }
post_note_safe(){
  local text="$1" hours="${2:-}"
  if [ -n "$hours" ]; then
    printf '{"text":%s,"hours":%s}\n' "$text" "$hours" \
    | curl -sS -w '\nHTTP:%{http_code}\n' -i -H 'Accept: application/json' -H 'Content-Type: application/json' \
      --data-binary @- "$BASE/api/notes"
  else
    printf '{"text":%s}\n' "$text" \
    | curl -sS -w '\nHTTP:%{http_code}\n' -i -H 'Accept: application/json' -H 'Content-Type: application/json' \
      --data-binary @- "$BASE/api/notes"
  fi
}

extract_json(){ awk 'BEGIN{p=0}/^\r?$/{p=1;next} p{print}'; }
extract_code(){ sed -n 's/^HTTP:\([0-9][0-9][0-9]\)$/\1/p'; }

echo "== HEALTH & DEPLOY =="
curl -sI "$BASE/api/health" | sed -n '1p'
DEPLOY="$(curl -fsS "$BASE/api/deploy-stamp" 2>/dev/null | jget '.commit')"
[ -n "$DEPLOY" ] && ok "deploy-stamp commit: $DEPLOY" || echo "(aviso) deploy-stamp no expuesto"
hr

echo "== TTL (horas) =="
MAXH="$(curl -sI "$BASE/" | awk 'BEGIN{IGNORECASE=1}/^X-Max-TTL-Hours:/{print $0}' | awk '{print $2}' || true)"
[ -n "$MAXH" ] && { [ "$MAXH" = "$TTL_EXPECTED" ] && ok "X-Max-TTL-Hours=$MAXH" || bad "X-Max-TTL-Hours=$MAXH (!=$TTL_EXPECTED)"; } \
               || echo "(aviso) X-Max-TTL-Hours ausente"

resp="$(post_note_safe '"ttl probe default"' )"
code="$(printf "%s" "$resp" | extract_code)"
body="$(printf "%s" "$resp" | extract_json)"
if [[ "$code" =~ ^2 ]]; then
  nid="$(printf "%s" "$body" | jget '.item.id')"
  [ -n "$nid" ] || { bad "POST default sin id (body: $body)"; exit 1; }
  full="$(curl -fsS "$BASE/api/notes/$nid")"
  ts="$(printf "%s" "$full" | jget '.item.timestamp')"
  exp="$(printf "%s" "$full" | jget '.item.expires_at')"
  ttl_hours="$(
python - "$ts" "$exp" <<'PY'
import sys,datetime as dt
ts,exp=sys.argv[1],sys.argv[2]
def p(s):
  try: return dt.datetime.fromisoformat(s.replace("Z","+00:00"))
  except: return dt.datetime.fromisoformat(s.split('.')[0])
t1,t2=p(ts),p(exp); print(f"{(t2-t1).total_seconds()/3600:.2f}")
PY
)"
  echo "· TTL por defecto: ${ttl_hours} h"; ok "default TTL medido"
else
  bad "POST /api/notes (default) → $code"
  echo "  Body: $body"
fi

huge=999999
resp2="$(post_note_safe '"ttl probe huge"'" $huge)"
code2="$(printf "%s" "$resp2" | extract_code)"
body2="$(printf "%s" "$resp2" | extract_json)"
if [[ "$code2" =~ ^2 ]]; then
  hid="$(printf "%s" "$body2" | jget '.item.id')"
  full2="$(curl -fsS "$BASE/api/notes/$hid")"
  ts2="$(printf "%s" "$full2" | jget '.item.timestamp')"
  exp2="$(printf "%s" "$full2" | jget '.item.expires_at')"
  cap_hours="$(
python - "$ts2" "$exp2" <<'PY'
import sys,datetime as dt
def p(s):
  try: return dt.datetime.fromisoformat(s.replace("Z","+00:00"))
  except: return dt.datetime.fromisoformat(s.split('.')[0])
t1,t2=p(sys.argv[1]),p(sys.argv[2])
print(int(round((t2-t1).total_seconds()/3600)))
PY
)"
  echo "· TTL con horas=$huge → ${cap_hours} h"
  [ "$cap_hours" -le "$TTL_EXPECTED" ] && ok "CAP TTL ≤ $TTL_EXPECTED" || bad "CAP TTL ${cap_hours} > ${TTL_EXPECTED}"
else
  echo "(aviso) no pude medir CAP; POST huge → $code2 Body: $body2"
fi
hr

echo "== LÍMITE DE CARACTERES =="
probe(){
  local n="$1"
  local payload="$(head -c "$n" /dev/zero | tr '\0' a | sed 's/.*/"&"/')"
  printf '{"text":%s}\n' "$payload" \
  | curl -sS -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' --data-binary @- "$BASE/api/notes" || true
}
sizes=(256 1024 4096 8192 16384 32768 65536 131072 262144)
maxok=0
for s in "${sizes[@]}"; do
  c="$(probe $s)"
  if [[ "$c" =~ ^2 ]]; then echo "· $s chars → $c OK"; maxok="$s"; else echo "· $s chars → $c"; break; fi
done
[ "$maxok" -gt 0 ] && ok "tamaño aceptado ≥ ${maxok}" || bad "POST 256 falló"
hr

echo "== LIKES 1×persona =="
nid2="$(printf '{"text":"likes probe"}' | curl -fsS -H 'Content-Type: application/json' --data-binary @- "$BASE/api/notes" | jget '.item.id')"
if [ -n "$nid2" ]; then
  a="$(curl -fsS -X POST "$BASE/api/notes/$nid2/like" | jget '.likes,.deduped' | paste -sd' ')"
  b="$(curl -fsS -X POST "$BASE/api/notes/$nid2/like" | jget '.likes,.deduped' | paste -sd' ')"
  echo "· same-FP => $a -> $b"
  if [ "$(echo "$a" | awk '{print $1}')" = "$(echo "$b" | awk '{print $1}')" ]; then ok "dedupe OK"; else bad "dedupe falló"; fi
else
  bad "no pude crear nota para likes (ver POST default)"
fi
hr

echo "RESUMEN: ok=$pass, fail=$fail"
[ $fail -eq 0 ] || exit 1
