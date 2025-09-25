#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: audit_frontend_lock_v1 BASE OUTDIR}"
OUT="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"

mkdir -p "$OUT"

# 1) Descargar HTML vivo con no SW + cache buster
V="$RANDOM$RANDOM"
curl -fsSL "$BASE/?debug=1&nosw=1&v=$V" -D "$OUT/index-h-$TS.txt" -o "$OUT/index-$TS.html" || true

# 2) Extraer headers clave
SIG=$(grep -i '^X-Frontend-Src:' "$OUT/index-h-$TS.txt" | sed 's/\r//')
CC=$(grep -i '^Cache-Control:' "$OUT/index-h-$TS.txt" | sed 's/\r//')

# 3) Validaciones HTML
LOC="frontend/index.html"
if [[ -f "$LOC" ]]; then cp -f "$LOC" "$OUT/index-local-$TS.html"; fi

# Conteos en vivo
TITLE_VIVO=$(grep -io '<title[^>]*>' "$OUT/index-$TS.html" | wc -l | tr -d ' ')
ADS_META_VIVO=$(grep -ic 'name=["'\'']google-adsense-account' "$OUT/index-$TS.html" || true)
ADS_SCRIPT_VIVO=$(grep -ic 'adsbygoogle\.js' "$OUT/index-$TS.html" || true)
VIEWS_SPAN_VIVO=$(grep -ic '<span[^>]*class=["'\''][^"'\''>]*views' "$OUT/index-$TS.html" || true)
TERMS_LINK_VIVO=$(grep -ic 'href=["'\'']/terms' "$OUT/index-$TS.html" || true)
PRIV_LINK_VIVO=$(grep -ic 'href=["'\'']/privacy' "$OUT/index-$TS.html" || true)

# 4) Hashes de comparación
if command -v sha256sum >/dev/null 2>&1; then
  SHA_LIVE=$(sha256sum "$OUT/index-$TS.html" | awk '{print $1}')
  if [[ -f "$OUT/index-local-$TS.html" ]]; then
    SHA_LOC=$(sha256sum "$OUT/index-local-$TS.html" | awk '{print $1}')
  else
    SHA_LOC="(no local)"
  fi
else
  SHA_LIVE="(no sha256sum)"
  SHA_LOC="(no sha256sum)"
fi

# 5) Reporte
REP="$OUT/frontend-lock-audit-$TS.txt"
{
  echo "== FRONTEND LOCK AUDIT =="
  echo "base : $BASE"
  echo "ts   : $TS"
  echo
  echo "-- Headers / --"
  sed 's/\r$//' "$OUT/index-h-$TS.txt" | sed -n '1,20p'
  echo
  echo "X-Frontend-Src: ${SIG:-'(missing)'}"
  echo "Cache-Control : ${CC:-'(missing)'}"
  echo
  echo "-- Checks HTML (vivo) --"
  echo "TITLE tags      : $TITLE_VIVO (esperado 1)"
  echo "AdSense meta    : $ADS_META_VIVO (>=1)"
  echo "AdSense script  : $ADS_SCRIPT_VIVO (>=1)"
  echo "span.views      : $VIEWS_SPAN_VIVO (>=1)"
  echo "link /terms     : $TERMS_LINK_VIVO (>=1)"
  echo "link /privacy   : $PRIV_LINK_VIVO (>=1)"
  echo
  echo "-- Hashes --"
  echo "live : $SHA_LIVE"
  echo "local: $SHA_LOC"
  echo
  echo "-- Archivos --"
  echo "  $OUT/index-$TS.html"
  [[ -f "$OUT/index-local-$TS.html" ]] && echo "  $OUT/index-local-$TS.html"
  echo "  $OUT/index-h-$TS.txt"
} | tee "$REP"

echo "Guardado: $REP"
