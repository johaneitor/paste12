#!/usr/bin/env bash
set -euo pipefail

BASE="${1:?Uso: $0 BASE_URL [OUT_DIR]}"
OUT="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"

mkdir -p "$OUT"

log() { printf '%s %s\n' "[$TS]" "$*" >&2; }

H="$OUT/api-notes-h-$TS.txt"
B="$OUT/api-notes-$TS.json"
O="$OUT/options-$TS.txt"
IH="$OUT/index-headers-$TS.txt"
I="$OUT/index-$TS.html"
HEALTH="$OUT/health-$TS.json"
SUM="$OUT/smoke-$TS.txt"

# 1) /api/health
log "health -> $HEALTH"
curl -fsS "$BASE/api/health" -o "$HEALTH" || true

# 2) OPTIONS /api/notes
log "options -> $O"
curl -sS -D - -o /dev/null -X OPTIONS "$BASE/api/notes" > "$O" || true

# 3) GET /api/notes (headers + body)
log "GET /api/notes headers -> $H ; body -> $B"
curl -sS -D - -o "$B" "$BASE/api/notes?limit=10" > "$H" || true

# 4) GET / (para ver HTML y headers)
log "GET / (index) -> $I ; headers -> $IH"
curl -sS -D "$IH" -o "$I" "$BASE/?debug=1&nosw=1&v=$TS" || true

# 5) Resumen
{
  echo "== SMOKE $TS =="
  echo "BASE: $BASE"
  echo
  echo "-- /api/health --"
  head -c 256 "$HEALTH" 2>/dev/null || echo "(sin archivo)"
  echo; echo
  echo "-- OPTIONS /api/notes --"
  head -n 20 "$O" 2>/dev/null || echo "(sin archivo)"
  echo
  echo "-- GET /api/notes (headers) --"
  head -n 20 "$H" 2>/dev/null || echo "(sin archivo)"
  echo
  echo "-- GET /api/notes (body, prefix) --"
  head -c 256 "$B" 2>/dev/null || echo "(sin archivo)"
  echo; echo
  echo "-- GET / (headers) --"
  head -n 20 "$IH" 2>/dev/null || echo "(sin archivo)"
  echo
  echo "-- GET / (html, prefix) --"
  head -n 20 "$I" 2>/dev/null || echo "(sin archivo)"
  echo
  echo "Archivos:"
  printf '  %s\n' "$HEALTH" "$O" "$H" "$B" "$IH" "$I"
  echo "== END =="
} > "$SUM"

log "Hecho. Resumen: $SUM"
