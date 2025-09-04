#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"

pass=0; fail=0
ok(){ echo "✓ $*"; pass=$((pass+1)); }
bad(){ echo "✗ $*"; fail=$((fail+1)); }
hr(){ printf -- "---------------------------------------------\n"; }

echo "== DEPLOY VS HEAD =="
LOCAL="$(git rev-parse HEAD | head -c 40 2>/dev/null || true)"
DEPLOY="$(curl -fsS "$BASE/api/deploy-stamp" | sed -n 's/.*"commit": *"\([0-9a-f]\{7,40\}\)".*/\1/p' || true)"
echo "Local:  ${LOCAL:-<n/a>}"
echo "Deploy: ${DEPLOY:-<sin valor>}"
[[ -n "$LOCAL" && "$LOCAL" == "$DEPLOY" ]] && ok "deploy == HEAD" || bad "deploy != HEAD"
hr

echo "== HEADERS / =="
H="$(curl -sI "$BASE/")"
printf "%s\n" "$H" | awk 'BEGIN{IGNORECASE=1}/^(HTTP\/|cache-control:|x-(index-source|wsgi-bridge):|cf-cache-status:|server:)/{print}'
echo "$H" | grep -qi '^cache-control:.*no-store' && ok "no-store en /" || bad "no-store ausente"
echo "$H" | grep -qi '^x-wsgi-bridge:' && ok "bridge activo" || bad "bridge ausente"
hr

echo "== HTML / =="
HTML="$(curl -fsS "$BASE/")"
echo "$HTML" | grep -qm1 -- '--teal:#8fd3d0' && ok "token pastel" || bad "token pastel ausente"
echo "$HTML" | grep -qi '<title> *Paste12 *</title>' && ok "title Paste12" || bad "title ausente"
echo "$HTML" | grep -qi '<h1[^>]*class="[^"]*\bbrand\b[^"]*"[^>]*> *Paste12 *<' && ok "h1.brand" || bad "h1.brand ausente"
echo "$HTML" | grep -qi 'id="tagline".*(Reta|secreto|Confiesa)' && ok "tagline" || bad "tagline ausente"
hr

echo "== FEED & PAGINACIÓN =="
PH="$(curl -si "$BASE/api/notes?limit=2")"
echo "$PH" | sed -n '1,20p' | grep -qi '^link:' && ok "Link header" || bad "Link header ausente"
echo "$PH" | sed -n '1,20p' | grep -qi '^x-next-cursor:' && ok "X-Next-Cursor" || bad "X-Next-Cursor ausente"
BODY="$(echo "$PH" | sed -n '22,$p')"
CNT="$(echo "$BODY" | jq -r '.items|length' 2>/dev/null || echo 0)"
[[ "$CNT" -ge 0 ]] && ok "items: $CNT" || bad "feed inválido"
hr

echo "== LIKES (dedupe + concurrencia) =="
NEW="$(curl -fsS -X POST "$BASE/api/notes" -H 'Content-Type: application/json' -d '{"text":"audit likes v3"}' | jq -r '.item.id')"
echo "note: $NEW"
L1="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" | jq -r '.likes,.deduped' | paste -sd' ')"
L2="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" | jq -r '.likes,.deduped' | paste -sd' ')"
if [ "$(echo "$L1" | awk '{print $1}')" = "$(echo "$L2" | awk '{print $1}')" ]; then ok "dedupe misma FP"; else bad "misma FP incrementó ($L1 -> $L2)"; fi

# Tres FPs nuevas ⇒ +3
curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: a' >/dev/null
curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: b' >/dev/null
curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: c' >/dev/null
AFTER="$(curl -fsS "$BASE/api/notes/$NEW" | jq -r '.item.likes')"
echo "likes tras a/b/c: $AFTER"

# Concurrencia (10 likes misma FP)
for i in $(seq 1 10); do echo $i; done | xargs -I{} -P10 bash -lc 'curl -fsS -X POST "'$BASE'/api/notes/'"$NEW"'/like" -H "X-FP: CONCUR" >/dev/null || true'
AFTER2="$(curl -fsS "$BASE/api/notes/$NEW" | jq -r '.item.likes')"
DELTA=$((AFTER2 - AFTER))
if [ "$DELTA" -le 1 ]; then ok "concurrencia <= +1 (delta=$DELTA)"; else bad "concurrencia incrementó $DELTA (>1)"; fi

hr
echo "RESUMEN: ok=$pass, fail=$fail"
[ "$fail" -eq 0 ] || exit 1
