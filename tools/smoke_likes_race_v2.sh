#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"

pass=0; fail=0
ok(){ echo "✓ $*"; pass=$((pass+1)); }
bad(){ echo "✗ $*"; fail=$((fail+1)); }
hr(){ printf -- "---------------------------------------------\n"; }
jget(){ jq -r "$1" 2>/dev/null || echo ""; }

echo "== CREATE (JSON largo) =="
NEW="$(jq -n --arg t "like probe $(date -u +%H:%M:%S) – texto largo para validar" '{text:$t}' \
  | curl -fsS -H 'Content-Type: application/json' --data-binary @- "$BASE/api/notes" \
  | jget '.item.id')"
[ -n "$NEW" ] && ok "nota creada id=$NEW" || { bad "no se pudo crear nota"; exit 1; }

hr
echo "== SAME-FP (dedupe) =="
one="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" | jq -r '.likes,.deduped' | paste -sd' ')"
two="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" | jq -r '.likes,.deduped' | paste -sd' ')"
echo "· same-FP => $one -> $two"
l1="$(echo "$one" | awk '{print $1}')"
l2="$(echo "$two" | awk '{print $1}')"
d2="$(echo "$two" | awk '{print $2}')"
{ [ "$l1" = "$l2" ] || [ "$d2" = "true" ]; } && ok "dedupe OK" || bad "dedupe falló"

hr
echo "== Concurrencia (10 likes misma FP; delta <= 1) =="
before="$(curl -fsS "$BASE/api/notes/$NEW" | jq -r '.item.likes')"
tmp_codes="$(mktemp)"
for i in $(seq 1 10); do
  (curl -sS -o /dev/null -w '%{http_code}\n' -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: Z' >> "$tmp_codes") &
  # un poco de jitter para evitar thundering herd
  usleep 50000 2>/dev/null || sleep 0.05
done
wait
after="$(curl -fsS "$BASE/api/notes/$NEW" | jq -r '.item.likes')"
delta=$((after-before))
echo "· antes=$before  despues=$after  delta=$delta"
dist="$(sort "$tmp_codes" | uniq -c | sed 's/^ *//')"
echo "· códigos: { $dist }"
rm -f "$tmp_codes"
[ "$delta" -le 1 ] && ok "concurrencia controlada (<= +1)" || bad "concurrencia +$delta (>1)"

hr
echo "== JSON shape (última respuesta) =="
resp="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like")"
echo "$resp" | jq -e '.ok,.id,.likes' >/dev/null 2>&1 && ok "JSON válido ok/id/likes" || bad "JSON inválido"

hr
echo "RESUMEN: ok=$pass, fail=$fail"
[ $fail -eq 0 ] || exit 1
