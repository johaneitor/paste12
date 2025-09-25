#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
OUT="${2:-/sdcard/Download}"

# Verificar OUT dir y fallback
try_out="$OUT"
mkdir -p "$try_out" 2>/dev/null || true
if ! (echo test > "$try_out/.wtest" 2>/dev/null); then
  echo "[warn] No puedo escribir en $try_out, uso \$HOME/Download"
  try_out="$HOME/Download"
  mkdir -p "$try_out"
fi
rm -f "$try_out/.wtest" 2>/dev/null || true

TS="$(date -u +%Y%m%d-%H%M%SZ)"
H="$try_out/health-$TS.json"
O="$try_out/options-$TS.txt"
A_H="$try_out/api-notes-h-$TS.txt"
A_B="$try_out/api-notes-$TS.json"
I_H="$try_out/index-headers-$TS.txt"
I_B="$try_out/index-$TS.html"

echo "health -> $H"
curl -fsS "$BASE/api/health" -o "$H" || echo '{"ok":false}' > "$H"

echo "options -> $O"
curl -fsSI -X OPTIONS "$BASE/api/notes" > "$O" || true

echo "GET /api/notes headers -> $A_H"
curl -fsSI "$BASE/api/notes" > "$A_H" || true

echo "index headers -> $I_H"
curl -fsSI "$BASE/" > "$I_H" || true

echo "index body -> $I_B"
curl -fsS "$BASE/?debug=1&nosw=1&v=$(date +%s)" -o "$I_B" || true

# Quick checks del HTML vivo
echo "-- quick checks --"
code=$(head -n1 "$I_H" 2>/dev/null || true)
echo "index code: ${code:-N/A}"
grep -qi '<meta[^>]*name=["'\'']google-adsense-account' "$I_B" && echo "OK - AdSense meta" || echo "FAIL - AdSense meta"
grep -q '<span[^>]*class=["'\''][^"'\''>]*\bviews\b' "$I_B" && echo "OK - span.views" || echo "FAIL - span.views"
