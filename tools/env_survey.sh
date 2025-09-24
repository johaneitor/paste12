#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"
have(){ command -v "$1" >/dev/null 2>&1; }
_json(){ if have jq; then jq -r "$1"; else python - "$1"; fi; }

echo "== REPO LOCAL =="
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  CWD=$(pwd)
  TOP=$(git rev-parse --show-toplevel)
  HEAD=$(git rev-parse HEAD)
  echo "cwd:     $CWD"
  echo "topdir:  $TOP"
  echo "HEAD:    $HEAD"
else
  echo "(no git repo detectado)"
fi
echo

echo "== DEPLOY REMOTO =="
REMOTE_JSON=$(curl -fsS "$BASE/api/deploy-stamp" || echo '')
if [ -n "$REMOTE_JSON" ]; then
  if have jq; then REMOTE=$(printf "%s" "$REMOTE_JSON" | jq -r '.commit // empty'); else REMOTE=$(printf "%s" "$REMOTE_JSON" | sed -n 's/.*"commit": *"\([0-9a-f]\{7,40\}\)".*/\1/p'); fi
  echo "REMOTE:  ${REMOTE:-<sin valor>}"
  if [ -n "${HEAD:-}" ] && [ -n "$REMOTE" ]; then
    if [ "$HEAD" = "$REMOTE" ]; then echo "=> MATCH (producción == HEAD local)"; else echo "=> MISMATCH (producción != HEAD local)"; fi
  fi
else
  echo "REMOTE: <sin respuesta>"
fi
echo

echo "== HEADERS / (sin caché) =="
curl -sI -H 'Cache-Control: no-cache' -H 'Pragma: no-cache' "$BASE/" \
 | awk 'BEGIN{IGNORECASE=1}/^(HTTP\/|cache-control:|x-index-source:|x-wsgi-bridge:|cf-cache-status:|server:)/{print}'
echo

echo "== HTML / (descarga fría) =="
TMP_HTML=$(mktemp)
curl -fsS -H 'Cache-Control: no-cache' -H 'Pragma: no-cache' "$BASE/" -o "$TMP_HTML" || true
SIZE=$(wc -c < "$TMP_HTML" 2>/dev/null || echo 0)
if have openssl; then SHA=$(openssl dgst -sha256 "$TMP_HTML" | awk '{print $2}'); else SHA=$(python - <<'PY'
import sys,hashlib;print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())
PY
"$TMP_HTML"); fi
echo "tamaño: ${SIZE} bytes   sha256: ${SHA}"

# Marcadores UI
if grep -q -- '--teal:#8fd3d0' "$TMP_HTML"; then echo "• token pastel: OK"; else echo "• token pastel: NO"; fi
grep -q 'Publicar' "$TMP_HTML"   && echo "• botón Publicar detectado"   || echo "• botón Publicar: NO"
grep -q '⋯' "$TMP_HTML"          && echo "• menú ⋯ detectado"            || echo "• menú ⋯: NO"
grep -q 'Compartir' "$TMP_HTML"  && echo "• acción Compartir detectada"  || echo "• acción Compartir: NO"
grep -q 'Reportar' "$TMP_HTML"   && echo "• acción Reportar detectada"   || echo "• acción Reportar: NO"
grep -q 'view-observer:start' "$TMP_HTML" && echo "• view-observer (auto-views) presente" || echo "• view-observer: NO"
echo

echo "== /api/health =="
curl -sI "$BASE/api/health" | sed -n '1p'
echo

echo "== GET /api/notes?limit=2 (headers) =="
curl -i -s "$BASE/api/notes?limit=2" | sed -n '1,20p'
echo "-- BODY --"
curl -s "$BASE/api/notes?limit=2" | (have jq && jq '{count: (.items|length), next}' || cat)
echo

echo "== HEAD /api/notes?limit=2 (sin cuerpo esperado) =="
curl -sI "$BASE/api/notes?limit=2" | awk 'BEGIN{IGNORECASE=1}/^(HTTP\/|content-length:|x-next-cursor:|link:)/{print}'
echo

echo "== Términos & Privacidad =="
curl -sI "$BASE/terms"   | sed -n '1p'
curl -sI "$BASE/privacy" | sed -n '1p'
# tamaño aproximado
TSZ=$(curl -fsS "$BASE/terms"   | wc -c || echo 0)
PSZ=$(curl -fsS "$BASE/privacy" | wc -c || echo 0)
echo "terms bytes: $TSZ   privacy bytes: $PSZ"
echo

echo "== Diag opcionales =="
# /api/notes_diag (si existe)
ND=$(curl -fsS "$BASE/api/notes_diag" || true)
if [ -n "$ND" ]; then
  if have jq; then printf "%s\n" "$ND" | jq 'del(.columns) | .dialect? // .ok?'; else echo "$ND"; fi
else
  echo "(sin /api/notes_diag)"
fi
# /api/bridge-state (si existe)
BS=$(curl -fsS "$BASE/api/bridge-state" || true)
[ -n "$BS" ] && echo "$BS" || echo "(sin /api/bridge-state)"
echo

echo "== RESUMEN =="
echo "- Deploy en HEAD local:   $( [ -n "${HEAD:-}" ] && [ -n "${REMOTE:-}" ] && [ "$HEAD" = "$REMOTE" ] && echo OK || echo NO )"
echo "- Bridge activo en /:     $(curl -sI "$BASE/" | grep -qi '^x-wsgi-bridge:' && echo SI || echo NO)"
echo "- no-store en /:          $(curl -sI "$BASE/" | grep -qi '^cache-control:.*no-store' && echo SI || echo NO)"
echo "- UI pastel visible:      $(grep -q -- '--teal:#8fd3d0' "$TMP_HTML" && echo SI || echo NO)"
echo "- Paginación headers:     $(curl -sI "$BASE/api/notes?limit=2" | grep -qi '^x-next-cursor:' && echo SI || echo NO)"
echo "- Terms/Privacy 200:      $(curl -sI "$BASE/terms" | head -n1 | grep -q '200' && curl -sI "$BASE/privacy" | head -n1 | grep -q '200' && echo SI || echo NO)"
rm -f "$TMP_HTML"
