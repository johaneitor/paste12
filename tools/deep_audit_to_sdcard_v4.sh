#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [[ -z "$BASE" ]] && { echo "Uso: $0 https://tu-app"; exit 2; }
OUTDIR="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
BE_TXT="$OUTDIR/backend-audit-$TS.txt"
FE_TXT="$OUTDIR/frontend-audit-$TS.txt"
IX_HTML="$OUTDIR/index-$TS.html"
DE_TXT="$OUTDIR/deploy-env-$TS.txt"
DE_JSON="$OUTDIR/deploy-env-$TS.json"

mkdir -p "$OUTDIR"

{
echo "== BACKEND AUDIT ($BASE) =="
echo "== /api/health =="
curl -fsS "$BASE/api/health" || true; echo; echo
echo "== OPTIONS /api/notes (CORS) =="
curl -fsSI -X OPTIONS "$BASE/api/notes" || true; echo
echo "== GET /api/notes?limit=3 (headers + body) =="
curl -fsSI "$BASE/api/notes?limit=3" || true; echo
curl -fsS  "$BASE/api/notes?limit=3" || true; echo
echo "== POST /api/notes (JSON) =="
curl -fsS -H 'Content-Type: application/json' -H 'Accept: application/json' \
     -d '{"text":"audit deep '"$TS"'"}' "$BASE/api/notes" || true; echo
echo "== POST /api/notes (FORM) =="
curl -fsSI -H 'Accept: application/json' \
     -d "text=audit deep $TS (form)" "$BASE/api/notes" || true; echo
curl -fsS  -H 'Accept: application/json' \
     -d "text=audit deep $TS (form)" "$BASE/api/notes" || true; echo
echo "== negativos (id inexistente) =="
for a in like view report; do
  printf "%s => HTTP/%s\n" "$a" "$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE/api/notes/999999/$a")"
done
echo
echo "== /api/deploy-stamp (txt/json) =="
curl -fsS "$BASE/api/deploy-stamp" -o "$DE_TXT" || true
curl -fsS -H 'Accept: application/json' "$BASE/api/deploy-stamp" -o "$DE_JSON" || true
echo "TXT: $(basename "$DE_TXT")  (size: $(wc -c < "$DE_TXT" 2>/dev/null || echo 0))"
echo "JSON: $(basename "$DE_JSON") (size: $(wc -c < "$DE_JSON" 2>/dev/null || echo 0))"
} > "$BE_TXT" 2>&1
echo "OK: $BE_TXT"

# Frontend básico
curl -fsS "$BASE/" -o "$IX_HTML" || true
echo "OK: $IX_HTML"
{
echo "== FRONTEND AUDIT ($BASE) =="
echo "bytes=$(wc -c < "$IX_HTML" 2>/dev/null || echo 0)"
grep -i -n '<meta name="p12-safe-shim"' "$IX_HTML" >/dev/null && echo "OK  - p12-safe-shim" || echo "info: p12-safe-shim (no encontrado, no bloqueante)"
} > "$FE_TXT" 2>&1
echo "OK: $FE_TXT"

echo "Listo."
