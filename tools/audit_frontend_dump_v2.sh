#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }

pick_dest() {
  for d in "$HOME/Download" "$HOME/downloads" "/sdcard/Download" "/storage/emulated/0/Download"; do
    if [ -d "$d" ] && [ -w "$d" ]; then echo "$d"; return; fi
  done
  mkdir -p "$HOME/downloads"; echo "$HOME/downloads"
}

DEST="$(pick_dest)"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
RAW_HTML="$DEST/index-$TS.html"
OUT_SUM="$DEST/frontend-overview-$TS.txt"
HDRS="/tmp/idx.$$.h"; BODY="/tmp/idx.$$.b"; rm -f "$HDRS" "$BODY"

# Importante: NO usar -f (para que igual guarde cuerpo en 4xx/5xx)
curl -sS -D "$HDRS" "$BASE/?_=$TS" -o "$BODY" || true
cp -f "$BODY" "$RAW_HTML"

BYTES="$(wc -c < "$BODY" | tr -d ' ')"
SCOUNT="$(grep -oi '<script[^>]*>' "$BODY" | wc -l | tr -d ' ')"
V7=$([ -s "$BODY" ] && grep -q 'name="p12-cohesion"' "$BODY" && echo "sí" || echo "no")

{
  echo "Frontend Overview — $TS"
  echo "BASE: $BASE"
  echo "Destino: $DEST"
  echo
  echo "HTTP status: $(sed -n '1s/^HTTP\/[0-9.]* //p' "$HDRS")"
  echo "Bytes HTML: $BYTES"
  echo "<script> tags: $SCOUNT"
  echo "Marcador v7: $V7"
  echo
  echo "Sugerencias:"
  echo "- Si Bytes=0, revisar conectividad o bloqueos."
  echo "- Abrir $BASE/?nosw=1&_=$TS para descartar SW viejo."
  echo "- Confirmar que la UI consuma Link/X-Next-Cursor para paginación."
} > "$OUT_SUM"

echo "OK: guardado"
echo "  HTML -> $RAW_HTML"
echo "  RES  -> $OUT_SUM"
