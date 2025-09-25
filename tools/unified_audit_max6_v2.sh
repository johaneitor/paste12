#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
OUTDIR="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"

mkdir -p "$OUTDIR"

H="$OUTDIR/health-$TS.json"
IH="$OUTDIR/index-headers-$TS.txt"
I="$OUTDIR/index-$TS.html"
AH="$OUTDIR/api-notes-headers-$TS.txt"
A="$OUTDIR/api-notes-$TS.json"
SUM="$OUTDIR/unified-audit-$TS.txt"

# 1) Health
curl -fsSL "$BASE/api/health" -o "$H" || echo '{"ok":false}' > "$H"

# 2) Index (headers + body) con bust
V=$RANDOM$RANDOM
curl -i -sS "$BASE/?nosw=1&nukesw=1&v=$V" -o "$IH" || true
curl -sS "$BASE/?nosw=1&nukesw=1&v=$V" -o "$I" || true

# 3) API notes (headers + body)
curl -i -sS "$BASE/api/notes?limit=10" -o "$AH" || true
curl -sS "$BASE/api/notes?limit=10" -o "$A" || echo "[]" > "$A"

# 4) Chequeos rápidos sobre index
HAS_META=$(grep -i -c 'google-adsense-account' "$I" || true)
HAS_JS=$(grep -i -c 'pagead2.googlesyndication.com/pagead/js/adsbygoogle.js' "$I" || true)
HAS_VIEWS=$(grep -i -c 'class="views"' "$I" || true)
HAS_LIKE=$(grep -c '/api/notes/\${id}/like' "$I" || true)  # buscamos la forma correcta con /
HAS_REPORT=$(grep -c '/api/notes/\${id}/report' "$I" || true)

# 5) Resumen
{
  echo "== Unified audit v2 =="
  echo "base: $BASE"
  echo "ts  : $TS"
  echo
  echo "-- health --"
  head -c 200 "$H" 2>/dev/null; echo
  echo
  echo "-- index quick checks --"
  code="$(head -n1 "$IH" 2>/dev/null | awk '{print $2" "$3}' || true)"
  echo "index code: ${code:-N/A}"
  [[ "$HAS_META" -gt 0 ]] && echo "OK  - AdSense meta" || echo "FAIL - AdSense meta"
  [[ "$HAS_JS" -gt 0 ]]   && echo "OK  - AdSense js"   || echo "FAIL - AdSense js"
  [[ "$HAS_VIEWS" -gt 0 ]]&& echo "OK  - span.views"   || echo "FAIL - span.views"
  [[ "$HAS_LIKE" -gt 0 ]] && echo "OK  - like endpoint"|| echo "FAIL - like endpoint"
  [[ "$HAS_REPORT" -gt 0 ]]&&echo "OK  - report endpoint"|| echo "FAIL - report endpoint"
  echo
  echo "-- api/notes headers --"
  head -n 20 "$AH" 2>/dev/null
  echo
  echo "Archivos:"
  echo "  $H"
  echo "  $IH"
  echo "  $I"
  echo "  $AH"
  echo "  $A"
} > "$SUM"

echo "Guardado: $SUM"
