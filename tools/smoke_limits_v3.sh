#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"
TTL_EXPECTED="${2:-2160}"
pass=0; fail=0
ok(){ echo "✓ $*"; pass=$((pass+1)); }
bad(){ echo "✗ $*"; fail=$((fail+1)); }
hr(){ printf -- "---------------------------------------------\n"; }
jget(){ jq -r "$1" 2>/dev/null || echo ""; }
extract_json(){ awk 'BEGIN{p=0}/^\r?$/{p=1;next} p{print}'; }
extract_code(){ sed -n 's/^HTTP:\([0-9][0-9][0-9]\)$/\1/p'; }

post_json(){
  local text="$1" hours="${2:-}"
  jq -n --arg t "$text" --argjson h "${hours:-null}" '{text:$t, hours:$h}' \
  | curl -sS -w '\nHTTP:%{http_code}\n' -i -H 'Accept: application/json' -H 'Content-Type: application/json' \
    --data-binary @- "$BASE/api/notes"
}

create_note_json(){
  local txt="nota verificada larga para pasar validación por longitud (>= 80 chars). 1234567890 abcdefghij"
  local resp code body nid
  resp="$(post_json "$txt")"
  code="$(printf "%s" "$resp" | extract_code)"
  body="$(printf "%s" "$resp" | extract_json)"
  if [[ "$code" =~ ^2 ]]; then
    nid="$(printf "%s" "$body" | jget '.item.id')"
    [ -n "$nid" ] && { echo "$nid"; return 0; }
  fi
  echo "POST JSON fail (code=$code) body=$body" >&2
  echo ""
  return 1
}

echo "== HEALTH & DEPLOY =="
curl -sI "$BASE/api/health" | sed -n '1p'
DEPLOY="$(curl -fsS "$BASE/api/deploy-stamp" 2>/dev/null | jget '.commit')"
[ -n "$DEPLOY" ] && ok "deploy-stamp commit: $DEPLOY" || echo "(aviso) deploy-stamp no expuesto"
hr

echo "== TTL (horas) =="
nid="$(create_note_json || true)"
if [ -n "$nid" ]; then
  full="$(curl -fsS "$BASE/api/notes/$nid")"
  ts="$(printf "%s" "$full" | jget '.item.timestamp')"
  exp="$(printf "%s" "$full" | jget '.item.expires_at')"
  if [ -n "$ts" ] && [ -n "$exp" ]; then
python - "$ts" "$exp" "$TTL_EXPECTED" <<'PY'
import sys,datetime as dt
def p(s):
  try: return dt.datetime.fromisoformat(s.replace("Z","+00:00"))
  except: return dt.datetime.fromisoformat(s.split('.')[0])
t1,t2=p(sys.argv[1]),p(sys.argv[2])
ttl=(t2-t1).total_seconds()/3600
print(f"· TTL por defecto: {ttl:.2f} h")
print("✓ default TTL medido")
PY
  else
    bad "no pude leer timestamp/expires_at"
  fi
else
  bad "no pude crear nota JSON para medir TTL"
fi
hr

echo "== LIKES 1×persona (JSON path) =="
nid2="$(create_note_json || true)"
if [ -n "$nid2" ]; then
  a="$(curl -fsS -X POST "$BASE/api/notes/$nid2/like" | jq -r '.likes,.deduped' | paste -sd' ' 2>/dev/null || true)"
  b="$(curl -fsS -X POST "$BASE/api/notes/$nid2/like" | jq -r '.likes,.deduped' | paste -sd' ' 2>/dev/null || true)"
  echo "· same-FP => $a -> $b"
  if [ "$(echo "$a" | awk '{print $1}')" = "$(echo "$b" | awk '{print $1}')" ]; then ok "dedupe OK"; else bad "dedupe falló"; fi
else
  bad "no pude crear nota para likes"
fi
hr

echo "RESUMEN: ok=$pass, fail=$fail"
[ $fail -eq 0 ] || exit 1
