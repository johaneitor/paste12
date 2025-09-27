#!/usr/bin/env bash
set -euo pipefail

BASE="${1:-https://paste12-rmsk.onrender.com}"
OUT="${2:-/sdcard/Download}"

ts="$(date -u +%Y%m%d-%H%M%SZ)"
bfile="$OUT/01-backend-$ts.txt"
pfile="$OUT/02-preflight-$ts.txt"
afile="$OUT/03-api-notes-$ts.txt"
ffile="$OUT/04-frontend-$ts.txt"
sfile="$OUT/05-summary-$ts.txt"

mkdir -p "$OUT"

line() { printf '%s\n' "--------------------------------------------------"; }

# 01) BACKEND
{
  echo "== 01 BACKEND =="
  echo "BASE: $BASE"
  echo "-- health headers --"
  curl -sS -i "$BASE/api/health" | sed -n '1,20p'
  echo
  echo "-- health body (primera línea) --"
  curl -sS "$BASE/api/health" | head -n1
} >"$bfile" || true

# 02) PREFLIGHT
{
  echo "== 02 PREFLIGHT (OPTIONS /api/notes) =="
  curl -sS -i -X OPTIONS "$BASE/api/notes"
  echo
  echo "-- expected headers --"
  cat <<'H'
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET, POST, HEAD, OPTIONS
Access-Control-Allow-Headers: Content-Type
Access-Control-Max-Age: 86400
H
} >"$pfile" || true

# 03) API NOTES (headers + cuerpo + Link)
{
  echo "== 03 API NOTES =="
  echo "-- headers --"
  curl -sS -i "$BASE/api/notes?limit=10" | tee /tmp/_api_headers.$$ | sed -n '1,25p'
  echo
  echo "-- Link header --"
  grep -i '^Link:' /tmp/_api_headers.$$ || echo "(no link header)"
  echo
  echo "-- body (primeras líneas) --"
  curl -sS "$BASE/api/notes?limit=10" | tee "$OUT/api-notes-$ts.json" | head -n 3
  rm -f /tmp/_api_headers.$$ || true
} >"$afile" || true

# 04) FRONTEND (vivo vs local)
{
  echo "== 04 FRONTEND (vivo vs local) =="
  live="$OUT/index-live-$ts.html"
  loc="$OUT/index-local-$ts.html"

  # Descarga vivo y copia local del repo (si existe)
  curl -sS "$BASE/" -o "$live" || true
  if [ -f frontend/index.html ]; then
    cp frontend/index.html "$loc"
  else
    echo "(WARN) No se encontró frontend/index.html local; solo se audita live."
  fi

  # Hashes
  if [ -f "$live" ]; then
    shal="$(sha256sum "$live" | awk '{print $1}')"
    echo "sha live: $shal"
  fi
  if [ -f "$loc" ]; then
    shac="$(sha256sum "$loc" | awk '{print $1}')"
    echo "sha local: $shac"
    if [ -f "$live" ]; then
      if [ "$shal" = "$shac" ]; then echo "OK- live coincide con repo"; else echo "WARN- live distinto al repo"; fi
    fi
  fi

  # Checks HTML (funcionales)
  check_html () {
    local file="$1"
    [ -f "$file" ] || { echo "(no existe $file)"; return 0; }
    local h1c vspan admeta adscript
    h1c="$(grep -c -i '<h1' "$file" || true)"
    vspan="$(grep -c -i '<span[^>]*class=.*views' "$file" || true)"
    admeta="$(grep -c -i 'meta[^>]*name=["'\'']google-adsense-account' "$file" || true)"
    adscript="$(grep -c -i 'adsbygoogle\.js' "$file" || true)"
    echo "file: $(basename "$file")  h1:$h1c  views-span:$vspan  ads-meta:$admeta  ads-script:$adscript"
  }

  echo "-- LIVE index --"
  check_html "$live"
  echo
  echo "-- LOCAL index --"
  check_html "$loc"

  echo
  echo "-- /terms --"
  curl -sS -i "$BASE/terms" | sed -n '1,12p'
  if curl -fsS "$BASE/terms" -o "$OUT/terms-$ts.html"; then check_html "$OUT/terms-$ts.html"; fi
  echo
  echo "-- /privacy --"
  curl -sS -i "$BASE/privacy" | sed -n '1,12p'
  if curl -fsS "$BASE/privacy" -o "$OUT/privacy-$ts.html"; then check_html "$OUT/privacy-$ts.html"; fi
} >"$ffile" || true

# 05) SUMMARY
{
  echo "== 05 SUMMARY =="
  echo "Archivos:"
  printf "  %s\n" "$bfile" "$pfile" "$afile" "$ffile" "$sfile" \
                 "$OUT/api-notes-$ts.json" "$OUT/index-live-$ts.html" "$OUT/index-local-$ts.html" \
                 "$OUT/terms-$ts.html" "$OUT/privacy-$ts.html"
  echo
  echo "-- Resumen rápido --"
  hb="$(grep -m1 '{' "$bfile" || true)"
  echo "health: ${hb:-(sin body)}"
  echo "preflight: $(grep -m1 '^HTTP/' "$pfile" || true)"
  echo "api-notes: $(grep -m1 '^HTTP/' "$afile" || true)"
  echo "link: $(grep -i -m1 '^Link:' "$afile" || echo '(no Link)')"
  echo
  echo "frontend live: $(grep -m1 '^file:' "$ffile" | sed -n '1p' || true)"
  echo "frontend local: $(grep -m1 '^file:' "$ffile" | sed -n '2p' || true)"
  echo
  echo "TIP: Si falta AdSense o <span class=\"views\"> en live, corre el reconciliador de frontend."
} >"$sfile" || true

echo "Guardados:"
printf "  %s\n" "$bfile" "$pfile" "$afile" "$ffile" "$sfile"
