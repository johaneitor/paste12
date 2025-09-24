#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"

pass=0; fail=0
ok(){ echo "✓ $*"; pass=$((pass+1)); }
bad(){ echo "✗ $*"; fail=$((fail+1)); }
hr(){ printf -- "---------------------------------------------\n"; }
jget(){ jq -r "$1" 2>/dev/null || echo ""; }

echo "== CREATE (JSON --data-binary, texto largo para pasar validación) =="
NEW="$(jq -n --arg t "like probe json con longitud suficiente para validar / $(date -u +%H:%M:%S)" '{text:$t}' \
  | curl -fsS -H 'Content-Type: application/json' --data-binary @- "$BASE/api/notes" \
  | jget '.item.id')"
[ -n "$NEW" ] && ok "nota creada id=$NEW" || { bad "no se pudo crear nota"; exit 1; }
hr

echo "== SAME-FP (dedupe) =="
first="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" | jq -r '.likes,.deduped' | paste -sd' ')"
second="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" | jq -r '.likes,.deduped' | paste -sd' ')"
echo "· same-FP => $first -> $second"
# Pasa si el número de likes no sube o si 'deduped' es true en el segundo
l1="$(echo "$first"  | awk '{print $1}')"
l2="$(echo "$second" | awk '{print $1}')"
d2="$(echo "$second" | awk '{print $2}')"
if [ "$l1" = "$l2" ] || [ "$d2" = "true" ]; then ok "dedupe misma FP OK"; else bad "dedupe misma FP falló"; fi
hr

echo "== FPs distintas (debe sumar +3) =="
A="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: A' | jq -r '.likes')"
B="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: B' | jq -r '.likes')"
C="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: C' | jq -r '.likes')"
echo "· A/B/C => $A -> $B -> $C"
FINAL="$(curl -fsS "$BASE/api/notes/$NEW" | jq -r '.item.likes')"
[ "$FINAL" = "4" ] && ok "likes finales = 4 (1 base + A+B+C)" || bad "likes finales = $FINAL (esperado 4)"
hr

echo "== Concurrencia (10 likes misma FP; delta <= 1) =="
before="$(curl -fsS "$BASE/api/notes/$NEW" | jq -r '.item.likes')"
seq 1 10 | xargs -I{} -P10 -n1 curl -fsS -o /dev/null -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: Z'
after="$(curl -fsS "$BASE/api/notes/$NEW" | jq -r '.item.likes')"
delta=$((after-before))
echo "· antes=$before  despues=$after  delta=$delta"
[ "$delta" -le 1 ] && ok "concurrencia controlada (<= +1)" || bad "concurrencia incrementó +$delta (>1)"
hr

echo "== JSON shape/200 (última respuesta del like) =="
resp="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like")"
echo "$resp" | jq -e '.ok,.id,.likes' >/dev/null 2>&1 && ok "JSON válido con ok/id/likes" || bad "JSON inválido"
hr

echo "RESUMEN: ok=$pass, fail=$fail"
[ $fail -eq 0 ] || exit 1
