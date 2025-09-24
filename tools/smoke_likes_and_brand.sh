#!/usr/bin/env bash
set -euo pipefail

BASE="${1:?Uso: $0 https://host}"
JQ_BIN="${JQ_BIN:-jq}"

say() { printf "%b\n" "$*"; }
hr()  { printf "%s\n" "---------------------------------------------"; }

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "Falta dependencia: $1"; exit 2; }
}

need curl
need awk
need grep
need sed
need "$JQ_BIN"

fail() { echo "✗ $*" >&2; exit 1; }
ok()   { echo "✓ $*"; }

say "== HEADERS / =="
HDRS="$(curl -fsSI "$BASE/" || true)"
echo "$HDRS" | awk 'BEGIN{IGNORECASE=1}/^(HTTP\/|x-wsgi-bridge:|x-index-source:|cache-control:|server:|cf-cache-status:)/{print}'
echo "$HDRS" | grep -qi '^HTTP/.* 200'          || fail "Raíz no devuelve 200"
echo "$HDRS" | grep -qi '^x-wsgi-bridge:'       && ok "Bridge activo (X-WSGI-Bridge)"
echo "$HDRS" | grep -qi '^cache-control: .*no-store' && ok "no-store presente en /"

hr
say "== HTML / (marca/tagline) =="
HTML="$(curl -fsS "$BASE/")"
echo "$HTML" | grep -q '<title>Paste12</title>'         && ok "title Paste12"        || fail "title Paste12 ausente"
echo "$HTML" | grep -q 'class="brand">Paste12</h1>'     && ok "marca Paste12 (h1)"   || fail "h1.brand Paste12 ausente"
echo "$HTML" | grep -q 'id="tagline"'                   && ok "tagline presente"     || fail "tagline ausente"
# aceptamos cualquier frase, pero si está alguna de éstas, lo anotamos
if echo "$HTML" | grep -Eq 'Reta a un amigo|Dime un secreto|Confiesa algo|Manda un reto|Anónimo o no'; then
  ok "frases lúdicas/ confesión detectadas"
else
  echo "• aviso: no detecté frases del tagline (puede estar en JS/rotando)"
fi

# (opcional) token pastel: solo informativo
if echo "$HTML" | grep -q -- '--teal:#8fd3d0'; then
  ok "token pastel presente"
else
  echo "• info: token pastel no detectado (no es bloqueo si UI está en JS)"
fi

hr
say "== Crear nota para pruebas de likes =="
TS="$(date -u +%FT%TZ)"
NEW_JSON="$(curl -fsS -X POST "$BASE/api/notes" -H 'content-type: application/json' \
  --data "{\"text\":\"smoke likes $TS\"}")" || fail "No pude crear nota"
NEW_ID="$(echo "$NEW_JSON" | "$JQ_BIN" -r '.item.id // .id')"
test -n "$NEW_ID" && ok "Nota creada id=$NEW_ID" || fail "No pude obtener id de la nota"

get_item() {
  curl -fsS "$BASE/api/notes/$1"
}

likes_of() {
  echo "$1" | "$JQ_BIN" -r '.item.likes // .likes // 0'
}

hr
say "== Estado inicial de likes =="
INIT="$(get_item "$NEW_ID")" || fail "No pude leer nota $NEW_ID"
L0="$(likes_of "$INIT")"
test "$L0" = "0" && ok "likes iniciales = 0" || fail "likes iniciales esperados 0, obtuve $L0"

hr
say "== 1) Like sin fingerprint (persona A) =="
curl -fsS -X POST "$BASE/api/notes/$NEW_ID/like" >/dev/null
A1_JSON="$(get_item "$NEW_ID")"
A1="$(likes_of "$A1_JSON")"
test "$A1" = "1" && ok "subió a 1" || fail "esperaba 1, obtuve $A1"

say "== 2) Re-like misma persona (A) (debe desduplicar) =="
curl -fsS -X POST "$BASE/api/notes/$NEW_ID/like" >/dev/null
A2_JSON="$(get_item "$NEW_ID")"
A2="$(likes_of "$A2_JSON")"
test "$A2" = "$A1" && ok "dedupe OK (sigue en $A2)" || fail "no dedupe: subió a $A2"

say "== 3) Like con X-FP: u2 (persona B) =="
curl -fsS -X POST "$BASE/api/notes/$NEW_ID/like" -H 'X-FP: u2' >/dev/null
B1_JSON="$(get_item "$NEW_ID")"
B1="$(likes_of "$B1_JSON")"
test "$B1" = "2" && ok "nuevo usuario: sube a 2" || fail "esperaba 2, obtuve $B1"

say "== 4) Re-like misma X-FP: u2 (B) (debe desduplicar) =="
curl -fsS -X POST "$BASE/api/notes/$NEW_ID/like" -H 'X-FP: u2' >/dev/null
B2_JSON="$(get_item "$NEW_ID")"
B2="$(likes_of "$B2_JSON")"
test "$B2" = "$B1" && ok "dedupe OK para B (sigue en $B2)" || fail "no dedupe para B: $B1 → $B2"

hr
say "== Resumen likes =="
echo "id=$NEW_ID  likes: inicial=$L0  tras A=$A1  re-A=$A2  tras B=$B1  re-B=$B2"
ok "Smoke de likes + verificación de marca/tagline finalizado OK"
