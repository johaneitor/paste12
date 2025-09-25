#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
OUT="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
mkdir -p "$OUT"

get() {
  local path="$1" tag="$2"
  local f="$OUT/${tag}-${TS}.html"
  curl -fsSL "$BASE$path" -o "$f" || true
  echo "$f"
}

hdr() {
  local path="$1" tag="$2"
  local f="$OUT/${tag}-headers-${TS}.txt"
  curl -sS -D - -o /dev/null "$BASE$path" > "$f" || true
  echo "$f"
}

IDX="$(get "/" index)"
IDXH="$(hdr "/" index)"
TER="$(get "/terms" terms)"
TERH="$(hdr "/terms" terms)"
PRI="$(get "/privacy" privacy)"
PRIH="$(hdr "/privacy" privacy)"

REP="$OUT/frontend-deep-audit-${TS}.txt"
{
  echo "== Frontend Deep Audit =="
  echo "base: $BASE"
  echo "ts  : $TS"
  echo
  echo "-- HEADERS / --"
  sed -n '1,40p' "$IDXH" 2>/dev/null || true
  echo
  for pair in "$IDX index" "$TER terms" "$PRI privacy"; do
    set -- $pair
    FILE="$1"; TAG="$2"
    echo "-- $TAG checks --"
    if [[ -s "$FILE" ]]; then
      META=$(grep -Eio '<meta[^>]+google-adsense-account[^>]*>' "$FILE" | wc -l || true)
      LOADER=$(grep -Eio 'googlesyndication\.com/pagead/js/adsbygoogle\.js\?client=' "$FILE" | wc -l || true)
      VIEWS=$(grep -Eio 'id=["'\''"]p12-stats["'\''"]' "$FILE" | wc -l || true)
      HASV=$(grep -Eio 'class=["'\''"][^"'\''>]*views' "$FILE" | wc -l || true)
      H1N=$(grep -Eio '<h1[^>]*>' "$FILE" | wc -l || true)
      echo "  META:   $META"
      echo "  LOADER: $LOADER"
      echo "  STATS:  $VIEWS (views-span: $HASV)"
      echo "  H1#:    $H1N"
      echo
    else
      echo "  (no response)"
    fi
  done
  echo "== Files =="
  echo "  $IDX"
  echo "  $TER"
  echo "  $PRI"
  echo "  $IDXH"
  echo "  $TERH"
  echo "  $PRIH"
} > "$REP"

echo "Guardado: $REP"
