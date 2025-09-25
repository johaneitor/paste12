#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
OUT="${2:-/sdcard/Download}"

# Salida segura
dst="$OUT"
mkdir -p "$dst" 2>/dev/null || true
if ! (echo test > "$dst/.wtest" 2>/dev/null); then
  echo "[warn] No puedo escribir en $dst, uso \$HOME/Download"
  dst="$HOME/Download"
  mkdir -p "$dst"
fi
rm -f "$dst/.wtest" 2>/dev/null || true

TS="$(date -u +%Y%m%d-%H%M%SZ)"

# 1) health
curl -fsS "$BASE/api/health" -o "$dst/health-$TS.json" || echo '{}' > "$dst/health-$TS.json"

# 2) OPTIONS /api/notes
curl -fsSI -X OPTIONS "$BASE/api/notes" > "$dst/options-$TS.txt" || true

# 3) HEAD+GET /api/notes
curl -fsSI "$BASE/api/notes" > "$dst/api-notes-headers-$TS.txt" || true
curl -fsS "$BASE/api/notes" -o "$dst/api-notes-$TS.json" || true

# 4) index (headers + body nocache)
curl -fsSI "$BASE/" > "$dst/index-headers-$TS.txt" || true
curl -fsS "$BASE/?debug=1&nosw=1&v=$(date +%s)" -o "$dst/index-$TS.html" || true

# 5) Términos y Privacidad (solo si responden 200)
for pg in terms privacy; do
  curl -fsSI "$BASE/$pg" > "$dst/${pg}-headers-$TS.txt" || true
  code=$(head -n1 "$dst/${pg}-headers-$TS.txt" 2>/dev/null | awk '{print $2}' || true)
  if [[ "${code:-}" == "200" ]]; then
    curl -fsS "$BASE/$pg" -o "$dst/${pg}-$TS.html" || true
  fi
done

# Resumen
R="$dst/unified-audit-$TS.txt"
{
  echo "== Unified audit =="
  echo "base: $BASE"
  echo "ts  : $TS"
  echo "-- health --"; cat "$dst/health-$TS.json" 2>/dev/null || true
  echo "-- OPTIONS /api/notes --"; head -n20 "$dst/options-$TS.txt" 2>/dev/null || true
  echo "-- GET /api/notes (headers) --"; head -n20 "$dst/api-notes-headers-$TS.txt" 2>/dev/null || true
  echo "-- GET /api/notes (body first line) --"; head -n1 "$dst/api-notes-$TS.json" 2>/dev/null || true
  echo "-- index (headers) --"; head -n20 "$dst/index-headers-$TS.txt" 2>/dev/null || true
  echo "-- index checks --"
  if grep -qi '<meta[^>]*name=["'\'']google-adsense-account' "$dst/index-$TS.html" 2>/dev/null; then echo "OK - AdSense meta"; else echo "FAIL - AdSense meta"; fi
  if grep -q '<span[^>]*class=["'\''][^"'\''>]*\bviews\b' "$dst/index-$TS.html" 2>/dev/null; then echo "OK - span.views"; else echo "FAIL - span.views"; fi
  echo
  echo "Archivos:"
  ls -1 "$dst" | grep "$TS" | sed "s|^|  $dst/|"
  echo "== END =="
} > "$R"
echo "Guardado: $R"
