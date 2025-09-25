#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
OUT="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"

mkdir -p "$OUT"

log(){ printf "[%s] %s\n" "$TS" "$*"; }

HEALTH="$OUT/health-$TS.json"
OPTS="$OUT/options-$TS.txt"
APIH="$OUT/api-notes-headers-$TS.txt"
APIB="$OUT/api-notes-$TS.json"
INDEXH="$OUT/index-headers-$TS.txt"
INDEXB="$OUT/index-$TS.html"
TERMESH="$OUT/terms-headers-$TS.txt"
TERMSB="$OUT/terms-$TS.html"
PRIVH="$OUT/privacy-headers-$TS.txt"
PRIVB="$OUT/privacy-$TS.html"
UNIFIED="$OUT/unified-audit-$TS.txt"

# -------- Backend health / CORS / API --------
curl -fsS "$BASE/api/health" -o "$HEALTH" || echo '{}' > "$HEALTH"
curl -fsSI -X OPTIONS "$BASE/api/notes" -o "$OPTS" || true
curl -fsSI "$BASE/api/notes?limit=10" -o "$APIH" || true
curl -fsS  "$BASE/api/notes?limit=10" -o "$APIB" || true

# -------- Frontend: index + headers --------
curl -fsSI "$BASE/" -o "$INDEXH" || true
curl -fsS  "$BASE/?debug=1&nosw=1&v=$RANDOM" -o "$INDEXB" || true

# -------- Legales --------
curl -fsSI "$BASE/terms"   -o "$TERMESH" || true
curl -fsS  "$BASE/terms"   -o "$TERMSB"  || true
curl -fsSI "$BASE/privacy" -o "$PRIVH"   || true
curl -fsS  "$BASE/privacy" -o "$PRIVB"   || true

# -------- Chequeos rápidos --------
ad_head="MISS"; ad_tag="MISS"; views="MISS"
if grep -qi 'name="google-adsense-account"' "$INDEXB"; then ad_head="HIT"; fi
if grep -qi 'pagead2.googlesyndication.com/pagead/js/adsbygoogle.js' "$INDEXB"; then ad_tag="HIT"; fi
if grep -qi '<span class="views"' "$INDEXB"; then views="HIT"; fi

# Extra: Link header/cursor para paginado
link_next="NONE"
if grep -qi '^link: .*rel="next"' "$APIH" 2>/dev/null; then
  link_next="$(grep -i '^link:' "$APIH" | sed -e 's/\r$//' )"
fi

# -------- Resumen legible --------
{
  echo "== Unified audit (final) =="
  echo "base: $BASE"
  echo "ts  : $TS"
  echo "-- health --"
  head -c 400 "$HEALTH" && echo
  echo
  echo "-- OPTIONS /api/notes --"
  if [[ -s "$OPTS" ]]; then cat "$OPTS"; else echo "(sin datos)"; fi
  echo
  echo "-- GET /api/notes headers --"
  if [[ -s "$APIH" ]]; then cat "$APIH"; else echo "(sin datos)"; fi
  echo
  echo "-- GET /api/notes body (primeras 2 líneas) --"
  if [[ -s "$APIB" ]]; then head -n2 "$APIB"; else echo "(sin datos)"; fi
  echo
  echo "-- index checks --"
  code_line="$(head -n1 "$INDEXH" 2>/dev/null || true)"
  echo "INDEX status: ${code_line:-N/A}"
  echo "AdSense meta: $ad_head"
  echo "AdSense tag : $ad_tag"
  echo "span.views  : $views"
  echo
  echo "-- legales --"
  echo "terms  : $(head -n1 "$TERMESH" 2>/dev/null || echo N/A)"
  echo "privacy: $(head -n1 "$PRIVH"  2>/dev/null || echo N/A)"
  echo
  echo "-- paginado --"
  echo "Link header: ${link_next}"
  echo
  echo "== Files =="
  printf "  %s\n" "$HEALTH" "$OPTS" "$APIH" "$APIB" "$INDEXH" "$INDEXB" "$TERMESH" "$TERMSB" "$PRIVH" "$PRIVB"
  echo "== END =="
} > "$UNIFIED"

echo "Guardado: $UNIFIED"
