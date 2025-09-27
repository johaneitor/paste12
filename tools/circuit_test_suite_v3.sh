#!/usr/bin/env bash
set -euo pipefail

BASE="${1:-https://paste12-rmsk.onrender.com}"
OUT="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
mkdir -p "$OUT"

b="$OUT/01-backend-$TS.txt"
p="$OUT/02-preflight-$TS.txt"
a="$OUT/03-api-notes-$TS.txt"
f="$OUT/04-frontend-$TS.txt"
s="$OUT/05-summary-$TS.txt"

# 01 BACKEND
{
  echo "== 01 BACKEND =="
  echo "BASE: $BASE"
  echo "-- health headers --"
  curl -sS -D - -o /dev/null "$BASE/api/health"
  echo
  echo "-- health body (primera línea) --"
  curl -sS "$BASE/api/health" | head -n1
} > "$b" || true

# 02 PREFLIGHT (OPTIONS)
{
  echo "== 02 PREFLIGHT (OPTIONS /api/notes) =="
  curl -sS -i -X OPTIONS "$BASE/api/notes"
  echo
  echo "-- expected headers --"
  echo "Access-Control-Allow-Origin: *"
  echo "Access-Control-Allow-Methods: GET, POST, HEAD, OPTIONS"
  echo "Access-Control-Allow-Headers: Content-Type"
  echo "Access-Control-Max-Age: 86400"
} > "$p" || true

# 03 API NOTES (GET)
{
  echo "== 03 API /api/notes (GET) =="
  echo "-- headers --"
  curl -sS -i "$BASE/api/notes?limit=10" | tee >(grep -i '^link:' || true) >/dev/null || true
  echo
  echo "-- body head (1 línea) --"
  curl -sS "$BASE/api/notes?limit=10" | head -n1 || true
  echo
  echo "-- link header (si hay) --"
  curl -sS -I "$BASE/api/notes?limit=10" | grep -i '^link:' || echo "NO LINK HEADER"
} > "$a" || true

# 04 FRONTEND (/, /terms, /privacy)
IDX="$OUT/index-$TS.html"
TRM="$OUT/terms-$TS.html"
PRV="$OUT/privacy-$TS.html"
curl -sS "$BASE/" -o "$IDX" || true
curl -sS "$BASE/terms" -o "$TRM" || true
curl -sS "$BASE/privacy" -o "$PRV" || true

count() { grep -oE "$1" "$2" | wc -l | tr -d ' '; }

{
  echo "== 04 FRONTEND (quick checks) =="
  echo "files:"
  echo "  $IDX"
  echo "  $TRM"
  echo "  $PRV"
  echo
  echo "-- index checks --"
  H1=$(count '<h1' "$IDX" || echo 0)
  VIEWS=$(count '<span[^>]*class="[^"]*views' "$IDX" || echo 0)
  ADSM=$(count '<meta[^>]+name=["'\'']google-adsense-account' "$IDX" || echo 0)
  ADSS=$(count 'pagead2\.googlesyndication\.com/pagead/js' "$IDX" || echo 0)
  echo "h1:$H1  views-span:$VIEWS  ads-meta:$ADSM  ads-script:$ADSS"
} > "$f" || true

# 05 SUMMARY
{
  echo "== 05 SUMMARY =="
  echo "BACKEND: $b"
  echo "PREFLIGHT: $p"
  echo "API: $a"
  echo "FRONTEND: $f"
  echo
  echo "-- quick verdict --"
  HOK=$(grep -q '"ok":true' "$b" && echo OK || echo FAIL)
  P204=$(grep -q '^HTTP/2 204' "$p" && echo OK || echo FAIL)
  A200=$(grep -q '^HTTP/2 200' "$a" && echo OK || echo FAIL)
  LNK=$(grep -qi '^link:' "$a" && echo OK || echo "WARN(no link)")
  FOK=$(grep -q 'views-span:.*[1-9]' "$f" && grep -q 'ads-meta:.*[1-9]' "$f" && grep -q 'ads-script:.*[1-9]' "$f" && echo OK || echo WARN)
  echo "health:$HOK  preflight:$P204  api:$A200  link:$LNK  fe:$FOK"
  echo
  echo "Archivos:"
  echo "  $b"
  echo "  $p"
  echo "  $a"
  echo "  $f"
} > "$s" || true

echo "Listo. Reportes:"
printf "%s\n%s\n%s\n%s\n%s\n" "$b" "$p" "$a" "$f" "$s"
