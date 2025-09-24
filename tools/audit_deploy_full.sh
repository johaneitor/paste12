#!/usr/bin/env bash
# Auditoría completa: guarda informe en ~/downloads/audit-YYYYmmdd-HHMMSSZ.txt
set -u -o pipefail

BASE="${1:-}"
CAP_HOURS="${2:-2160}" # cap de TTL esperado (horas), sólo informativo
[ -n "$BASE" ] || { echo "Uso: $0 https://host [ttl_cap_horas]"; exit 2; }

mkdir -p "$HOME/downloads" "${TMPDIR:-$HOME/tmp}"
TMP="${TMPDIR:-$HOME/tmp}/audit.$$.tmp"
OUT="$HOME/downloads/audit-$(date -u +%Y%m%d-%H%M%SZ).txt"

w() { echo -e "$*" | tee -a "$OUT" >/dev/null; }
sep(){ w "---------------------------------------------"; }

w "== HEALTH & DEPLOY =="
HSTAT="$(curl -sS -i "$BASE/api/health" -o "$TMP" -w '%{http_code}')"
w "HTTP/$HSTAT"
if [ "$HSTAT" -ge 200 ] && [ "$HSTAT" -lt 300 ]; then
  if command -v jq >/dev/null 2>&1; then
    COMMIT="$(jq -r '.deploy.commit // empty' < "$TMP")"
    DATE="$(jq -r '.deploy.date // empty' < "$TMP")"
    [ -n "$COMMIT" ] && w "✓ deploy-stamp commit: $COMMIT"
    [ -n "$DATE" ]   && w "✓ deploy-stamp fecha: $DATE"
  else
    head -n 60 "$TMP" | tee -a "$OUT" >/dev/null
  fi
else
  w "✗ /api/health no OK. Preview:"; head -n 80 "$TMP" | tee -a "$OUT" >/dev/null
fi
sep

w "== HEADERS / =="
curl -sS -I "$BASE/" | tee -a "$OUT" >/dev/null || true
sep

w "== CONNECT META =="
curl -sS "$BASE/" -o /dev/null -w 'ip=%{remote_ip} http=%{http_version} code=%{http_code} dns=%{time_namelookup}s conn=%{time_connect}s tls=%{time_appconnect}s ttfb=%{time_starttransfer}s total=%{time_total}s\n' | tee -a "$OUT" >/dev/null
sep

w "== CORS (OPTIONS /api/notes) =="
curl -sS -i -X OPTIONS "$BASE/api/notes" \
  -H 'Origin: https://example.com' \
  -H 'Access-Control-Request-Method: POST' | sed -n '1,80p' | tee -a "$OUT" >/dev/null
sep

w "== CREATE NOTE (JSON y FORM) =="
JID="$(
  printf '{"text":"audit %s texto para validar 1234567890 abcdefghij"}' "$(date -u +%H:%M:%SZ)" |
  curl -fsS -H 'Content-Type: application/json' --data-binary @- "$BASE/api/notes" |
  { command -v jq >/dev/null 2>&1 && jq -r '.item.id // .id // empty' || cat; }
)"
[ -n "$JID" ] && w "✓ JSON id: $JID" || w "✗ JSON no creó id"

FID="$(
  curl -fsS -H 'Content-Type: application/x-www-form-urlencoded' \
    --data "text=audit+$(date -u +%H%3AM%3ASZ)+form+1234567890+abcdefghijkl" \
    "$BASE/api/notes" | { command -v jq >/dev/null 2>&1 && jq -r '.item.id // .id // empty' || cat; }
)"
[ -n "$FID" ] && w "✓ FORM id: $FID" || w "✗ FORM no creó id"
sep

USE_ID="${FID:-$JID}"
if [ -n "$USE_ID" ]; then
  w "== TTL (GET /api/notes/:id) =="
  curl -sS -D "$TMP.headers" "$BASE/api/notes/$USE_ID" -o "$TMP.body" >/dev/null || true
  head -n 1 "$TMP.headers" | tee -a "$OUT" >/dev/null
  CC="$(grep -i '^Cache-Control:' "$TMP.headers" | head -n1 | cut -d' ' -f2-)"
  if echo "$CC" | grep -qi 'max-age'; then
    MA="$(echo "$CC" | sed -n 's/.*max-age=\([0-9]\+\).*/\1/p')"
    if [ -n "$MA" ]; then
      H=$(( MA / 3600 ))
      w "TTL medido: ${H}.00 h (cap esperado: ${CAP_HOURS} h)"
      [ "$H" -le "$CAP_HOURS" ] && w "OK: TTL ≤ cap" || w "⚠ TTL > cap"
    else
      w "(sin max-age en Cache-Control)"
    fi
  else
    w "(sin Cache-Control max-age)"
  fi
  sep
fi

w "== LIKES (dedupe + concurrencia) =="
if [ -n "$USE_ID" ]; then
  BEFORE="$(curl -fsS "$BASE/api/notes/$USE_ID" | { command -v jq >/dev/null 2>&1 && jq -r '.item.likes // .likes // 0' || echo 0; })"
  w "likes antes: ${BEFORE}"
  L1="$(curl -sS -X POST "$BASE/api/notes/$USE_ID/like" | { command -v jq >/dev/null 2>&1 && jq -r '.likes // empty' || cat; })"
  L2="$(curl -sS -X POST "$BASE/api/notes/$USE_ID/like" | { command -v jq >/dev/null 2>&1 && jq -r '.likes // empty' || cat; })"
  w "same-FP: $L1 -> $L2 (esperado: no subir el segundo)"
  CODES="$(for i in 1 2 3 4 5; do curl -s -o /dev/null -w '%{http_code} ' -X POST "$BASE/api/notes/$USE_ID/like"; done)"
  AFTER="$(curl -fsS "$BASE/api/notes/$USE_ID" | { command -v jq >/dev/null 2>&1 && jq -r '.item.likes // .likes // 0' || echo 0; })"
  DELTA=$(( ${AFTER:-0} - ${BEFORE:-0} ))
  w "concurrencia: antes=$BEFORE despues=$AFTER delta=$DELTA"
  w "códigos: { $CODES}"
else
  w "(omitido: no hubo id para probar likes)"
fi
sep

w "== PAGINACIÓN (limit=5) =="
curl -sS -D "$TMP.p.h" "$BASE/api/notes?limit=5" -o "$TMP.p.b" >/dev/null || true
echo "status: $(sed -n '1p' "$TMP.p.h")" | tee -a "$OUT" >/dev/null
grep -i '^Link:' "$TMP.p.h"   | tee -a "$OUT" >/dev/null || true
grep -i '^X-Next-Cursor:' "$TMP.p.h" | tee -a "$OUT" >/dev/null || true
if command -v jq >/dev/null 2>&1; then
  jq -r '.items[]?.id' < "$TMP.p.b" | sed 's/^/id: /' | tee -a "$OUT" >/dev/null
else
  head -n 60 "$TMP.p.b" | tee -a "$OUT" >/dev/null
fi
sep

w "== UI (index.html heurística) =="
curl -sS "$BASE/index.html" -o "$TMP.index" || true
if grep -qi 'paste12\|brand' "$TMP.index"; then
  w "brand: OK"
else
  w "brand: (no encontrado, podría ser fallback del bridge o deploy parcial)"
fi
sep

w "== DIAGNÓSTICO RÁPIDO =="
HEAD_CODE="$(curl -s -o /dev/null -w '%{http_code}' "$BASE/")"
HEALTH_CODE="$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/health")"
case "$HEAD_CODE" in
  502|503) w "• / ⇒ $HEAD_CODE → runner/instancia no lista o warmup fallido (deploy-level)";;
  404)     w "• / ⇒ 404 → puente/bridge no sirviendo index (revisa _root_force_mw o rutas)";;
  200)     w "• / ⇒ 200 → capa HTTP OK";;
  *)       w "• / ⇒ $HEAD_CODE → revisar logs del proveedor";;
esac
case "$HEALTH_CODE" in
  200) w "• /api/health ⇒ 200 → app cargó OK";;
  404) w "• /api/health ⇒ 404 → rutas no montadas";;
  500) w "• /api/health ⇒ 500 → excepción en arranque";;
  502|503) w "• /api/health ⇒ $HEALTH_CODE → despliegue caído en runtime";;
  *)   w "• /api/health ⇒ $HEALTH_CODE";;
esac

w ""
w "INFORME: $OUT"
echo "Listo: $OUT"
