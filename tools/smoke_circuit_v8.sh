#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Usa: tools/smoke_circuit_v8.sh https://tuapp.onrender.com}"
OUTDIR="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
mkdir -p "$OUTDIR"

B="$OUTDIR/01-backend-$TS.txt"
P="$OUTDIR/02-preflight-$TS.txt"
N="$OUTDIR/03-api-notes-$TS.txt"
F="$OUTDIR/04-frontend-$TS.txt"
S="$OUTDIR/05-summary-$TS.txt"

{ echo "== 01 BACKEND =="; echo "BASE: $BASE";
  echo "-- health headers --"; curl -si "$BASE/api/health" | sed -n '1,20p';
  echo; echo "-- health body (primera línea) --"; curl -s "$BASE/api/health" | head -n1; echo;
} > "$B" || true

{ echo "== 02 PREFLIGHT (OPTIONS /api/notes) ==";
  curl -si -X OPTIONS "$BASE/api/notes" | sed -n '1,40p'; echo;
  cat <<'EXP'
-- expected headers --
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET, POST, HEAD, OPTIONS
Access-Control-Allow-Headers: Content-Type
Access-Control-Max-Age: 86400
EXP
} > "$P" || true

{ echo "== 03 API NOTES (GET) ==";
  echo "-- headers --"; curl -si "$BASE/api/notes?limit=10" | sed -n '1,60p'; echo;
  echo "-- body (first 200 chars) --"; curl -s "$BASE/api/notes?limit=10" | head -c 200; echo;
} > "$N" || true

{ echo "== 04 FRONTEND (index) ==";
  curl -si "$BASE/" | sed -n '1,20p'; echo;
  curl -s "$BASE/" | tee "$OUTDIR/index-$TS.html" >/dev/null;
  echo "-- checks --";
  MET=$(grep -c 'name="google-adsense-account"' "$OUTDIR/index-$TS.html" || true)
  TAG=$(grep -c 'adsbygoogle' "$OUTDIR/index-$TS.html" || true)
  H1s=$(grep -ci '<h1' "$OUTDIR/index-$TS.html" || true)
  VWS=$(grep -c 'class="views"' "$OUTDIR/index-$TS.html" || true)
  echo "ads-meta:$MET ads-script:$TAG h1:$H1s views-span:$VWS";
} > "$F" || true

{ echo "== 05 SUMMARY ==";
  echo "BACKEND:   $B"; echo "PREFLIGHT: $P"; echo "API-NOTES: $N"; echo "FRONTEND:  $F"; echo;
  echo "Interpretación rápida:";
  echo "- health.ok debe ser true y api true.";
  echo "- OPTIONS: 204 con ACAO:* y métodos/headers esperados.";
  echo "- GET /api/notes: 200 con JSON válido (al menos items:[]).";
  echo "- index: meta/script AdSense, un solo <h1>, span.views.";
} > "$S" || true

echo "Archivos:"
printf "  %s\n" "$B" "$P" "$N" "$F" "$S"
