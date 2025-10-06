#!/usr/bin/env bash
set -Eeuo pipefail
BASE="${1:?Uso: $0 BASE_URL OUTDIR}"
OUT="${2:?Uso: $0 BASE_URL OUTDIR}"
ts="$(date -u +%Y%m%d-%H%M%SZ)"
work="$HOME/tmp/verify-$ts"; mkdir -p "$work" "$OUT"
sum="$OUT/verify-$ts-summary.txt"
pos="$OUT/verify-$ts-positivos.txt"
neg="$OUT/verify-$ts-negativos.txt"
lim="$OUT/verify-$ts-limits.txt"

w(){ printf "%s\n" "$*" | tee -a "$sum"; }
pp(){ printf "%s\n" "$*" >> "$pos"; }
nn(){ printf "%s\n" "$*" >> "$neg"; }
ll(){ printf "%s\n" "$*" >> "$lim"; }

code(){ curl -s -o /dev/null -w '%{http_code}' "$1" || echo 000; }
json_post(){
  curl -sS -D "$work/headers-post.txt" -o "$work/body-post.json" \
    -H 'Content-Type: application/json' \
    --data '{"title":"p12 smoke","text":"Hola paste12","ttl_hours":24}' \
    "$BASE/api/notes" || true
  sed -i 's/\r$//' "$work/headers-post.txt" || true
  status="$(sed -n '1s/.* //p' "$work/headers-post.txt" | tr -dc '0-9')"
  echo "${status:-000}"
}
form_post(){
  curl -sS -D "$work/headers-postf.txt" -o "$work/body-postf.json" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode "title=p12 smoke f" \
    --data-urlencode "text=Hola form" \
    --data-urlencode "ttl_hours=24" \
    "$BASE/api/notes" || true
  sed -i 's/\r$//' "$work/headers-postf.txt" || true
  status="$(sed -n '1s/.* //p' "$work/headers-postf.txt" | tr -dc '0-9')"
  echo "${status:-000}"
}
extract_id(){
  # intenta JSON {"id":123} o Location: ...?id=123
  sed -n 's/.*"id"[": ]*\([0-9]\{1,20\}\).*/\1/p' "$1" | head -1 ||
  sed -n 's/.*[?&]id=\([0-9]\{1,20\}\).*/\1/p' "$1" | head -1
}

# ========= POSITIVOS =========
pp "• == POSITIVOS =="
pp "• GET /: $(code "$BASE/")"
pp "• GET /terms: $(code "$BASE/terms")"
pp "• GET /privacy: $(code "$BASE/privacy")"
pp "• GET /api/notes?limit=10: $(code "$BASE/api/notes?limit=10")"

allow=$(curl -sD - -o /dev/null -X OPTIONS "$BASE/api/notes" 2>/dev/null | tr -d '\r' | sed -n 's/^allow: //Ip' | tr -d '\n')
pp "• OPTIONS /api/notes Allow: ${allow:-<vacío>}"

s_json="$(json_post)"
pp "• POST /api/notes [json]: $s_json"
new_id="$(extract_id "$work/body-post.json" || true)"
if [[ -z "${new_id:-}" || ! "$s_json" =~ ^2[0-9][0-9]$ ]]; then
  s_form="$(form_post)"
  pp "• POST /api/notes [form]: $s_form"
  [[ -z "$new_id" ]] && new_id="$(extract_id "$work/body-postf.json" || true)"
fi
[[ -z "${new_id:-}" ]] && pp "• Nota creada: <no-id>"

# ========= NEGATIVOS =========
nn "• == NEGATIVOS =="
nn "• like?id inexistente: $(code "$BASE/api/like?id=99999999") (esperado 404)"
nn "• view GET id inexistente: $(code "$BASE/api/view?id=99999999") (404)"
nn "• view POST id inexistente: $(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/api/view" || echo 000) (404)"
nn "• report?id inexistente: $(code "$BASE/api/report?id=99999999") (404)"
# REST style (si existen)
nn "• REST like inexistente: $(code "$BASE/api/notes/99999999/like") (404 esperado si implementado)"
nn "• REST report inexistente: $(code "$BASE/api/notes/99999999/report") (404 esperado si implementado)"

# ========= LÍMITES / VISTAS / ANTI-ABUSO =========
ll "• == LÍMITES (TTL/CAP) & vistas & anti-abuso =="
if [[ -n "${new_id:-}" ]]; then
  v1="$(code "$BASE/api/view?id=$new_id")"
  v2="$(code "$BASE/api/view?id=$new_id")"
  ll "• view x2 nueva nota $new_id: $v1,$v2 (200 esperado; el backend debe contar vistas)"
  # comprobar NEXT y tamaño de página
  curl -sS "$BASE/api/notes?limit=3" -o "$work/list3.json" || true
  next="$(sed -n 's/.*"next"[": ]*"\([^"]*\)".*/\1/p' "$work/list3.json" | head -1)"
  has_next="$([[ -n "${next:-}" ]] && echo yes || echo no)"
  ll "• list limit=3 -> next: $has_next"
  # anti-abuso básico: rate-limit visible?
  hdr="$(curl -sD - -o /dev/null "$BASE/api/notes?limit=3" | tr -d '\r' | sed -n 's/^x-rate.*//p' | head -1)"
  ll "• rate-limit headers (si expone): ${hdr:-<N/A>}"
else
  ll "• CREATE_UNAVAILABLE → SKIP vistas/NEXT/limits (arreglar POST 2xx primero)"
fi

# ========= RESUMEN =========
pass_pos="OK"
grep -qE ' 4..$| 5..$' <<<"$(tail -n +1 "$pos")" && pass_pos="FAIL"

pass_neg="OK"
# en negativos, 200 es FAIL; 404 es OK
bad_neg_lines="$(grep -E ' 200$' "$neg" || true)"
[[ -n "$bad_neg_lines" ]] && pass_neg="FAIL"

pass_lim="OK"
grep -q 'CREATE_UNAVAILABLE' "$lim" && pass_lim="SKIP"

w "----- RESUMEN (verify) -----"
w "• POSITIVOS: $pass_pos"
w "• NEGATIVOS: $pass_neg"
w "• LÍMITES  : $pass_lim"
w "Archivos:"
w "  - $pos"
w "  - $neg"
w "  - $lim"
