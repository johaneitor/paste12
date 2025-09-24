#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"

pass=0; fail=0
ok(){ printf "✓ %s\n" "$*"; pass=$((pass+1)); }
bad(){ printf "✗ %s\n" "$*"; fail=$((fail+1)); }
hr(){ printf -- "---------------------------------------------\n"; }

echo "== DEPLOY VS HEAD =="
LOCAL="$(git rev-parse HEAD 2>/dev/null | head -c 40 || true)"
REMOTE="$(curl -fsS "$BASE/api/deploy-stamp" | sed -n 's/.*"commit": *"\([0-9a-f]\{7,40\}\)".*/\1/p' || true)"
echo "Local:  ${LOCAL:-<n/a>}"
echo "Remote: ${REMOTE:-<sin valor>}"
if [ -n "${LOCAL:-}" ] && [ -n "${REMOTE:-}" ] && [ "$LOCAL" = "$REMOTE" ]; then ok "producción == HEAD local"; else bad "producción != HEAD local (ojo: auto-deploy/builde cache)"; fi
hr

echo "== HEADERS / =="
H="$(curl -sI "$BASE/")" || true
printf "%s\n" "$H" | awk 'BEGIN{IGNORECASE=1}/^(HTTP\/|cache-control:|x-(index-source|wsgi-bridge):|server:|cf-cache-status:)/{print}'
printf "%s\n" "$H" | grep -qi '^cache-control:.*no-store' && ok "no-store presente en /" || bad "no-store ausente en /"
printf "%s\n" "$H" | grep -qi '^x-wsgi-bridge:' && ok "Bridge activo (X-WSGI-Bridge)" || bad "Bridge no detectado"
hr

echo "== HTML / (descarga fría) =="
HTML="$(curl -fsS "$BASE/")"
sz="$(printf "%s" "$HTML" | wc -c | awk '{print $1}')"
sha="$(printf "%s" "$HTML" | sha256sum | awk '{print $1}')"
echo "tamaño: ${sz} bytes   sha256: ${sha}"
printf "%s" "$HTML" | grep -qm1 -- '--teal:#8fd3d0' && ok "token pastel" || bad "token pastel ausente"
printf "%s" "$HTML" | grep -qi '<title> *Paste12 *</title>' && ok "<title>Paste12</title>" || bad "título Paste12 ausente"
printf "%s" "$HTML" | grep -qi '<h1[^>]*class="[^"]*\bbrand\b[^"]*"[^>]*> *Paste12 *<' && ok "h1.brand Paste12" || bad "h1.brand ausente"
printf "%s" "$HTML" | grep -qi 'id="tagline".*(Reta|secreto|Confiesa)' && ok "tagline lúdico" || bad "tagline ausente"
# Heurística UI:
printf "%s" "$HTML" | grep -qi 'class="post' && ok "botón Publicar detectado" || true
printf "%s" "$HTML" | grep -qi 'class="act more"' && ok "menú ⋯ detectado" || true
printf "%s" "$HTML" | grep -qi '>Compartir<' && ok "acción Compartir" || true
printf "%s" "$HTML" | grep -qi '>Reportar' && ok "acción Reportar" || true
hr

echo "== HEALTH & PAGINACIÓN =="
curl -sI "$BASE/api/health" | head -n1 | grep -q "200" && ok "health 200" || bad "health no-200"
PH="$(curl -si "$BASE/api/notes?limit=2")"
printf "%s\n" "$PH" | sed -n '1,20p' | grep -qi '^link:' && ok "Link header next" || bad "Link header ausente"
printf "%s\n" "$PH" | sed -n '1,20p' | grep -qi '^x-next-cursor:' && ok "X-Next-Cursor header" || bad "X-Next-Cursor ausente"
BODY="$(printf "%s" "$PH" | sed -n '22,$p')"
cnt="$(printf "%s" "$BODY" | jq -r '.items|length' 2>/dev/null || echo 0)"
[ "$cnt" -ge 1 ] && ok "feed items: $cnt" || bad "feed vacío"
hr

echo "== HEAD /api/notes?limit=2 (sin cuerpo) =="
HH="$(curl -si -X HEAD "$BASE/api/notes?limit=2")"
printf "%s\n" "$HH" | grep -qi '^HTTP/.* 200' && ok "HEAD 200" || bad "HEAD no-200"
# Si tu backend setea Content-Length: 0 en HEAD, marcamos OK
printf "%s\n" "$HH" | grep -qi '^content-length: *0' && ok "HEAD sin cuerpo (CL=0)" || echo "(aviso) HEAD podría tener cuerpo"

hr
echo "== SMOKE LIKES (dedupe 1×persona) =="
NEW="$(curl -fsS -X POST "$BASE/api/notes" -H 'Content-Type: application/json' -d '{"text":"audit likes smoke"}' | jq -r '.item.id')"
echo "nota id: $NEW"

# Lectura base de likes
BASELIKES="$(curl -fsS "https://paste12-rmsk.onrender.com/api/notes/$NEW" | jq -r '.item.likes // 0' 2>/dev/null || echo 0)"
echo "likes base: ${BASELIKES}"

# 1) Misma FP dos veces → debe quedar igual
L1="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" | jq -r '.likes')"
L2="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" | jq -r '.likes')"
if [ "$L1" = "$L2" ]; then ok "dedupe misma FP OK ($L1)"; else bad "dedupe falla ($L1 -> $L2)"; fi

# 2) Tres FPs nuevas → +3
A="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: A' | jq -r '.likes')"
B="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: B' | jq -r '.likes')"
C="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: C' | jq -r '.likes')"
echo "likes tras A/B/C: $A -> $B -> $C"
# 3) Ataque concurrente (10 likes misma FP) → debe +1 como mucho
b4="$(curl -fsS "https://paste12-rmsk.onrender.com/api/notes/$NEW" | jq -r '.item.likes // 0' 2>/dev/null || echo 0)"
seq 1 10 | xargs -I{} -P 10 curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: CONC' >/dev/null
b5="$(curl -fsS "https://paste12-rmsk.onrender.com/api/notes/$NEW" | jq -r '.item.likes // 0' 2>/dev/null || echo 0)"
delta=$((b5 - b4))
if [ "$delta" -le 1 ]; then ok "concurrencia (misma FP) segura (+$delta)"; else bad "concurrencia incrementó $delta (>1)"; fi

hr
echo "== RUTEO likes (alias opcional) =="
# Comprueba si /api/like/<id> responde (alias). No es error si 404.
ALIAS="$(curl -si -X POST "$BASE/api/like/$NEW" | sed -n '1p')"
printf "%s\n" "$ALIAS" | grep -q " 200" && ok "alias /api/like/:id activo" || echo "(aviso) alias /api/like/:id no disponible"

hr
echo "== Términos & Privacidad =="
curl -sI "$BASE/terms" | head -n1 | grep -q "200" && ok "/terms 200" || bad "/terms no-200"
curl -sI "$BASE/privacy" | head -n1 | grep -q "200" && ok "/privacy 200" || bad "/privacy no-200"

hr
echo "== RESUMEN =="
echo "OK:   $pass"
echo "FALLA:$fail"
[ "$fail" -eq 0 ] || exit 1
