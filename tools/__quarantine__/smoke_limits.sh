#!/usr/bin/env bash
set -euo pipefail

BASE="${1:?Uso: $0 https://host}"
TTL_EXPECTED="${2:-2160}"   # horas (por defecto 3 meses = 2160h)

pass=0; fail=0
ok(){ echo "✓ $*"; pass=$((pass+1)); }
bad(){ echo "✗ $*"; fail=$((fail+1)); }
hr(){ printf -- "---------------------------------------------\n"; }

# --- helpers ---
jget(){ jq -r "$1" 2>/dev/null || echo ""; }
post_note(){
  local text="$1" hours="${2:-}"
  if [ -n "$hours" ]; then
    curl -fsS -X POST "$BASE/api/notes" \
      -H 'Content-Type: application/json' \
      -d "{\"text\":$text,\"hours\":$hours}"
  else
    curl -fsS -X POST "$BASE/api/notes" \
      -H 'Content-Type: application/json' \
      -d "{\"text\":$text}"
  fi
}
get_note(){ curl -fsS "$BASE/api/notes/$1"; }

# (A) Salud y deploy
echo "== HEALTH & DEPLOY =="
curl -sI "$BASE/api/health" | sed -n '1p'
DEPLOY="$(curl -fsS "$BASE/api/deploy-stamp" 2>/dev/null | jget '.commit')"
[ -n "$DEPLOY" ] && ok "deploy-stamp commit: $DEPLOY" || echo "(aviso) deploy-stamp no expuesto (500/404)"

hr

# (B) TTL real y CAP por servidor
echo "== TTL (horas) =="
# 1) cabecera anunciada (si existe)
MAXH="$(curl -sI "$BASE/" | awk 'BEGIN{IGNORECASE=1}/^X-Max-TTL-Hours:/{print $0}' | awk '{print $2}' || true)"
if [ -n "${MAXH:-}" ]; then
  [ "$MAXH" = "$TTL_EXPECTED" ] && ok "Header X-Max-TTL-Hours=$MAXH (esperado $TTL_EXPECTED)" \
                                || bad "X-Max-TTL-Hours=$MAXH (esperado $TTL_EXPECTED)"
else
  echo "(aviso) X-Max-TTL-Hours no está en /, seguimos con medición empírica"
fi

# 2) TTL por defecto (diff entre expires_at y timestamp)
new_json="$(post_note '"ttl probe default"')" || { bad "POST /api/notes (default)"; exit 1; }
nid="$(printf "%s" "$new_json" | jget '.item.id')"
[ -n "$nid" ] || { bad "no id en POST default"; exit 1; }
full="$(get_note "$nid")"
ts="$(printf "%s" "$full" | jget '.item.timestamp')"
exp="$(printf "%s" "$full" | jget '.item.expires_at')"

ttl_hours="$(
python - "$ts" "$exp" <<'PY'
import sys,datetime as dt
ts,exp=sys.argv[1],sys.argv[2]
# tolera "YYYY-mm-dd HH:MM:SS.sss+00:00"
def parse(s):
    try: return dt.datetime.fromisoformat(s.replace("Z","+00:00"))
    except: 
        # último intento: sin microseg
        return dt.datetime.fromisoformat(s.split('.')[0])
t1,t2=parse(ts),parse(exp)
print(f"{(t2-t1).total_seconds()/3600:.2f}")
PY
)"
echo "· TTL por defecto: ${ttl_hours} h"
ok "default TTL medido (${ttl_hours} h)"

# 3) CAP efectivo: intentar horas enormes (se acepta JSON.hours? si no, cae al default)
huge=999999
j_huge="$(post_note '"ttl probe huge"'" $huge 2>/dev/null || true)"
hid="$(printf "%s" "$j_huge" | jget '.item.id')"
if [ -n "$hid" ]; then
  full2="$(get_note "$hid")"
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
  [ "$cap_hours" -le "$TTL_EXPECTED" ] && ok "CAP TTL ≤ $TTL_EXPECTED h" || bad "CAP TTL ${cap_hours} > ${TTL_EXPECTED} h"
else
  echo "(aviso) el backend ignora JSON.hours; no se midió CAP directo (se usa default)"
fi

hr

# (C) Límite de caracteres (búsqueda rápida)
echo "== LÍMITE DE CARACTERES (nota.text) =="
probe(){
  local n="$1"
  local payload="$(head -c "$n" /dev/zero | tr '\0' a | sed 's/.*/"&"/')"
  code=$(curl -sS -o /tmp/p -w '%{http_code}' -X POST "$BASE/api/notes" \
    -H 'Content-Type: application/json' -d "{\"text\":${payload}}") || code=$?
  echo "$code"
}
# Escalado exponencial hasta fallar o 64k
sizes=(256 1024 4096 8192 16384 32768 65536 131072 262144)
maxok=0 last=0
for s in "${sizes[@]}"; do
  c="$(probe $s)"
  if [[ "$c" =~ ^2 ]]; then maxok="$s"; last="$c"; echo "· $s chars → $c OK"
  else echo "· $s chars → $c"; break; fi
done
if [ "$maxok" -gt 0 ]; then ok "tamaño aceptado >= ${maxok} chars"; else bad "POST básico no aceptó 256"; fi

hr

# (D) Likes: 1×persona
echo "== LIKES (1×persona) =="
nid2="$(post_note '"likes probe"'" | jget '.item.id')"
[ -n "$nid2" ] || { bad "no id para likes"; exit 1; }
a="$(curl -fsS -X POST "$BASE/api/notes/$nid2/like" | jget '.likes,.deduped' | paste -sd' ')"
b="$(curl -fsS -X POST "$BASE/api/notes/$nid2/like" | jget '.likes,.deduped' | paste -sd' ')"
echo "· same-FP => $a -> $b"
if [ "$(echo "$a" | awk '{print $1}')" = "$(echo "$b" | awk '{print $1}')" ]; then
  ok "dedupe misma FP OK"
else
  bad "dedupe misma FP falló"
fi
# 3 FPs nuevas
curl -fsS -X POST "$BASE/api/notes/$nid2/like" -H 'X-FP: A' >/dev/null || true
curl -fsS -X POST "$BASE/api/notes/$nid2/like" -H 'X-FP: B' >/dev/null || true
curl -fsS -X POST "$BASE/api/notes/$nid2/like" -H 'X-FP: C' >/dev/null || true
final_likes="$(curl -fsS "$BASE/api/notes/$nid2" | jget '.item.likes')"
echo "· likes finales (esperado 4): $final_likes"
[ "$final_likes" = "4" ] && ok "likes por persona correcto" || bad "likes finales = $final_likes"

hr

# (E) Reportes: umbral observable (mejor esfuerzo)
echo "== REPORTES (best-effort) =="
nid3="$(post_note '"report probe"'" | jget '.item.id')"
[ -n "$nid3" ] || { echo "(aviso) no pude crear nota para reportes)"; }
changes=0
for fp in A B C D E F; do
  curl -fsS -X POST "$BASE/api/notes/$nid3/report" -H "X-FP: $fp" >/dev/null || true
  # intentamos leerla; si desaparece del feed de 50, asumimos alcanzó umbral
  in_feed="$(curl -fsS "$BASE/api/notes?limit=50" | jq -r '.items[].id' | grep -c "^$nid3$" || true)"
  if [ "$in_feed" -eq 0 ]; then changes=1; echo "· umbral alcanzado (probablemente ocultada)"; break; fi
done
[ "$changes" -eq 1 ] && ok "umbral de reportes activo (oculta/filtra)" || echo "(aviso) no se observó ocultamiento en 6 reportes)"

hr

# (F) Tasa / rate-limit rudimentario (10 POST seguidos)
echo "== RATE LIMIT (rudimentario) =="
failp=0
for i in $(seq 1 10); do
  c=$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$BASE/api/notes" \
      -H 'Content-Type: application/json' -d "{\"text\":\"rate $i\"}")
  [[ "$c" =~ ^2 ]] || failp=$((failp+1))
done
[ "$failp" -eq 0 ] && ok "sin 429/4xx en ráfaga de 10" || bad "hubo $failp fallos en ráfaga (posible limitación)"

hr
echo "RESUMEN: ok=$pass, fail=$fail"
[ $fail -eq 0 ] || exit 1
