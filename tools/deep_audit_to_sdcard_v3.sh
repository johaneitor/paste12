#!/usr/bin/env bash
set -euo pipefail

BASE="${1:-}"
if [[ -z "$BASE" ]]; then
  echo "Uso: $0 https://tu-app.onrender.com" >&2
  exit 1
fi

OUTDIR="/sdcard/Download"
mkdir -p "$OUTDIR"
TS="$(date -u +%Y%m%d-%H%M%SZ)"

BACKEND_TXT="$OUTDIR/backend-audit-$TS.txt"
FRONTEND_TXT="$OUTDIR/frontend-audit-$TS.txt"
INDEX_HTML="$OUTDIR/index-$TS.html"
FE_BE_TXT="$OUTDIR/fe-be-audit-$TS.txt"
ENV_TXT="$OUTDIR/deploy-env-$TS.txt"
ENV_JSON="$OUTDIR/deploy-env-$TS.json"

# Nota: NO usamos -f para que curl no corte con 400/404
CURL="curl -sS --max-time 20 --connect-timeout 10 -L"

pass=0; fail=0
ok(){ echo "OK  - $*"; ((pass++)); }
ko(){ echo "FAIL- $*"; ((fail++)); }
hr(){ printf '%*s\n' 70 | tr ' ' '─'; }

: > "$BACKEND_TXT"
: > "$FRONTEND_TXT"
: > "$FE_BE_TXT"

# ========== BACKEND ==========
{
  echo "== BACKEND AUDIT ($BASE) =="
  hr

  echo "== /api/health =="
  code="$($CURL -o /dev/null -w '%{http_code}' "$BASE/api/health" || true)"
  body="$($CURL "$BASE/api/health" || true)"
  echo "HTTP $code"
  echo "$body"
  echo

  echo "== OPTIONS /api/notes (CORS) =="
  $CURL -i -X OPTIONS "$BASE/api/notes" 2>&1 | sed -n '1,60p' || true
  echo

  echo "== GET /api/notes?limit=3 (headers + body) =="
  $CURL -i "$BASE/api/notes?limit=3" 2>&1 | sed -n '1,60p' || true
  echo
  $CURL "$BASE/api/notes?limit=3" 2>&1 | sed -n '1,200p' || true
  echo

  echo "== POST /api/notes (JSON) =="
  note_text="audit deep $TS"
  json_resp="$($CURL -H 'Content-Type: application/json' -d "{\"text\":\"$note_text\"}" "$BASE/api/notes" || true)"
  echo "$json_resp"
  nid="$(printf '%s' "$json_resp" | python - <<'PY' 2>/dev/null || true
import sys, json
try:
  d=json.loads(sys.stdin.read()); print(d.get("id",""))
except Exception: pass
PY
)"
  echo "id extraído: ${nid:-<vacío>}"
  echo

  echo "== POST /api/notes (FORM) =="
  $CURL -i -H 'Content-Type: application/x-www-form-urlencoded' -d "text=$note_text (form)" "$BASE/api/notes" 2>&1 | sed -n '1,80p' || true
  echo

  echo "== like/view/report en existente (si hay id) =="
  if [[ -n "${nid:-}" ]]; then
    echo "-- like --"
    $CURL -i -X POST "$BASE/api/notes/$nid/like" 2>&1 | sed -n '1,40p' || true
    echo "-- view --"
    $CURL -i -X POST "$BASE/api/notes/$nid/view" 2>&1 | sed -n '1,40p' || true
    echo "-- report --"
    $CURL -i -X POST "$BASE/api/notes/$nid/report" 2>&1 | sed -n '1,40p' || true
  else
    echo "(no se extrajo id; se omite)"
  fi
  echo

  echo "== negativos (id inexistente) =="
  for a in like view report; do
    nc="$($CURL -o /dev/null -w '%{http_code}' -X POST "$BASE/api/notes/999999/$a" || true)"
    echo "$a => HTTP $nc"
  done
  echo

  echo "== /api/deploy-stamp (txt/json) =="
  $CURL "$BASE/api/deploy-stamp" -o "$ENV_TXT" || true
  $CURL "$BASE/api/deploy-stamp.json" -o "$ENV_JSON" || true
  echo "TXT: $(basename "$ENV_TXT")  (size: $(wc -c < "$ENV_TXT" 2>/dev/null || echo 0))"
  echo "JSON: $(basename "$ENV_JSON") (size: $(wc -c < "$ENV_JSON" 2>/dev/null || echo 0))"

} >> "$BACKEND_TXT"

# ========== FRONTEND ==========
{
  echo "== FRONTEND AUDIT ($BASE) =="
  hr

  echo "== GET / (index.html) => $INDEX_HTML =="
  $CURL "$BASE/" -o "$INDEX_HTML" || true
  bytes="$(wc -c < "$INDEX_HTML" 2>/dev/null || echo 0)"
  echo "bytes=$bytes"
  echo

  echo "== HEAD / y /index.html =="
  $CURL -I "$BASE/" 2>&1 | sed -n '1,40p' || true
  echo
  $CURL -I "$BASE/index.html" 2>&1 | sed -n '1,40p' || true
  echo

  echo "== Chequeos simples en index.html =="
  if [[ "$bytes" -gt 200 ]]; then
    echo "OK index bytes > 200"
  else
    echo "WARN index chico ($bytes bytes)"
  fi
  grep -q "p12-safe-shim" "$INDEX_HTML" 2>/dev/null && echo "OK p12-safe-shim" || echo "info: p12-safe-shim ausente (tolerado)"
} >> "$FRONTEND_TXT"

# ========== FE + BE RESUMEN ==========
{
  echo "== FE/BE RESUMEN =="
  hr

  body="$($CURL "$BASE/api/health" || true)"
  if [[ "$body" == '{"ok":true}' ]]; then ok "health JSON"; else ko "health body: $body"; fi

  hdrs="$($CURL -i -X OPTIONS "$BASE/api/notes" | sed -n '1,120p' || true)"
  echo "$hdrs" | head -1 | grep -qE '^HTTP/.* 204 ' && ok "OPTIONS 204" || ko "OPTIONS 204"
  echo "$hdrs" | grep -qi '^Access-Control-Allow-Origin:'  && ok "ACAO" || ko "ACAO"
  echo "$hdrs" | grep -qi '^Access-Control-Allow-Methods:' && ok "ACAM" || ko "ACAM"
  echo "$hdrs" | grep -qi '^Access-Control-Allow-Headers:' && ok "ACAH" || ko "ACAH"
  echo "$hdrs" | grep -qi '^Access-Control-Max-Age:'       && ok "Max-Age" || ko "Max-Age"

  hdrn="$($CURL -i "$BASE/api/notes?limit=3" | sed -n '1,80p' || true)"
  echo "$hdrn" | head -1 | grep -qE '^HTTP/.* 200 ' && ok "GET /api/notes 200" || ko "GET /api/notes 200"
  echo "$hdrn" | grep -qi '^content-type: *application/json' && ok "CT json" || ko "CT json"
  echo "$hdrn" | grep -qi '^link:' && ok "Link presente" || ko "Link ausente"

  if [[ -s "$INDEX_HTML" && "$(wc -c < "$INDEX_HTML")" -gt 200 ]]; then
    ok "index bytes > 200"
  else
    ko "index tamaño"
  fi

  echo
  echo "RESUMEN: PASS=$pass FAIL=$fail"
} >> "$FE_BE_TXT"

echo "OK: $BACKEND_TXT"
echo "OK: $FRONTEND_TXT"
echo "OK: $FE_BE_TXT"
[[ -s "$ENV_TXT"  ]] && echo "OK: $ENV_TXT"  || echo "info: $ENV_TXT vacío o no disponible"
[[ -s "$ENV_JSON" ]] && echo "OK: $ENV_JSON" || echo "info: $ENV_JSON vacío o no disponible"
echo "OK: $INDEX_HTML"
