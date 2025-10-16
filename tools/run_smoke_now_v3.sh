#!/usr/bin/env bash
set -euo pipefail

BASE="${1:?Uso: $0 BASE_URL [OUT_DIR]}"
OUT="${2:-$(pwd)/e2e-artifacts}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"

mkdir -p "$OUT"
log() { printf '%s %s\n' "[$TS]" "$*" >&2; }

H="$OUT/api-notes-h-$TS.txt"
B="$OUT/api-notes-$TS.json"
O="$OUT/options-$TS.txt"
IH="$OUT/index-headers-$TS.txt"
I="$OUT/index-$TS.html"
HEALTH="$OUT/health-$TS.json"
JS_H="$OUT/jsapp.js.headers-$TS.txt"
CSS_H="$OUT/cssstyles.css.headers-$TS.txt"
SUM="$OUT/smoke-$TS.txt"

log "health -> $HEALTH"
curl -fsS "$BASE/api/health" -o "$HEALTH" || true

log "options -> $O"
curl -sS -D - -o /dev/null -X OPTIONS "$BASE/api/notes" > "$O" || true

log "GET /api/notes headers -> $H ; body -> $B"
curl -sS -D - -o "$B" "$BASE/api/notes?limit=10" > "$H" || true

log "GET / (index) -> $I ; headers -> $IH"
curl -sS -D "$IH" -o "$I" "$BASE/?debug=1&nosw=1&v=$TS" || true

# Recolectar headers de recursos estáticos comunes (si están referenciados)
ROOT_URLS=$(grep -Eoi 'src="[^"]+|href="[^"]+' "$I" | cut -d'"' -f2 | sed -E 's#^//#https://#')
JS_URL=$(printf '%s\n' "$ROOT_URLS" | grep -E '/(app|main)\.js(\?|$)' | head -1 || true)
CSS_URL=$(printf '%s\n' "$ROOT_URLS" | grep -E '/(styles|main|app)\.css(\?|$)' | head -1 || true)

if [[ -n "${JS_URL:-}" ]]; then
  log "GET js -> $JS_H"
  curl -sS -D "$JS_H" -o /dev/null "$JS_URL" || true
fi
if [[ -n "${CSS_URL:-}" ]]; then
  log "GET css -> $CSS_H"
  curl -sS -D "$CSS_H" -o /dev/null "$CSS_URL" || true
fi

{
  echo "== SMOKE $TS =="
  echo "BASE: $BASE"
  echo
  echo "-- /api/health --"; head -c 256 "$HEALTH" 2>/dev/null || echo "(sin archivo)"; echo; echo
  echo "-- OPTIONS /api/notes --"; head -n 20 "$O" 2>/dev/null || echo "(sin archivo)"; echo
  echo "-- GET /api/notes (headers) --"; head -n 20 "$H" 2>/dev/null || echo "(sin archivo)"; echo
  echo "-- GET /api/notes (body, prefix) --"; head -c 256 "$B" 2>/dev/null || echo "(sin archivo)"; echo; echo
  echo "-- GET / (headers) --"; head -n 20 "$IH" 2>/dev/null || echo "(sin archivo)"; echo
  echo "-- GET / (html, prefix) --"; head -n 20 "$I" 2>/dev/null || echo "(sin archivo)"; echo
  if [[ -f "$JS_H" ]]; then echo "-- js headers --"; head -n 20 "$JS_H"; echo; fi
  if [[ -f "$CSS_H" ]]; then echo "-- css headers --"; head -n 20 "$CSS_H"; echo; fi
  echo "Archivos:"; printf '  %s\n' "$HEALTH" "$O" "$H" "$B" "$IH" "$I" "$JS_H" "$CSS_H"
  echo "== END =="
} > "$SUM"

log "Hecho. Resumen: $SUM"
