#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
source "$(dirname "$0")/_tmpdir.sh"

pick(){ for d in "/sdcard/Download" "/storage/emulated/0/Download" "$HOME/Download" "$HOME/downloads"; do
  [ -d "$d" ] && [ -w "$d" ] && { echo "$d"; return; }; done; echo "$HOME"; }

DEST="$(pick)"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
OUT_TXT="$DEST/deploy-env-$TS.txt"
OUT_JSON="$DEST/deploy-env-$TS.json"

TMPD="$(mkd)"; trap 'rm -rf "$TMPD"' EXIT
H="$TMPD/h.txt"; J="$TMPD/j.json"

echo "timestamp: $TS"           > "$OUT_TXT"
echo "base: $BASE"             >> "$OUT_TXT"
echo                           >> "$OUT_TXT"

# 1) Cabeceras de index (para contexto)
{
  echo "== HEADERS / (index) ==";      curl -sS -i "$BASE/"          | sed -n '1,20p'
  echo; echo "== HEADERS /index.html =="; curl -sS -i "$BASE/index.html" | sed -n '1,20p'
  echo; echo "== HEADERS /?nosw=1 =="; curl -sS -i "$BASE/?nosw=1"   | sed -n '1,20p'
  echo; echo "== HEALTH /api/health ==";  curl -sS "$BASE/api/health"
  echo
} >> "$OUT_TXT" || true

# 2) Snapshot JSON: /diag/import
URL="$BASE/diag/import"
code=$(curl -sS --compressed -w '%{http_code}' -D "$H" "$URL" -o "$J" || true)

clen=$(awk 'BEGIN{IGNORECASE=1} /^Content-Length:/ {print $2}' "$H" | tr -d '\r' || true)
ctype=$(awk 'BEGIN{IGNORECASE=1} /^Content-Type:/ {print $2}' "$H" | tr -d '\r' || true)
size=$(wc -c < "$J" | tr -d ' ')

{
  echo "== ENV SNAPSHOT ($URL) -> $(basename "$OUT_JSON") =="
  echo
  echo "== RUNTIME SUMMARY =="
  echo "http_code: $code"
  echo "content_type: ${ctype:-n/a}"
  echo "content_length_hdr: ${clen:-n/a}"
  echo "body_size: $size"
  echo
  echo "== ENV (whitelist) =="
  # extrae algunas claves si hay JSON
  if [ "$code" = "200" ] && [ "$size" -gt 0 ]; then
    echo "- ok: body looks present"
  else
    echo "- warning: cuerpo vacío o status != 200 (no se moverá JSON a Download)"
  fi
  echo
} >> "$OUT_TXT"

# 3) Guardado condicional del JSON
if [ "$code" = "200" ] && [ "$size" -gt 0 ]; then
  mv "$J" "$OUT_JSON"
  echo "OK: $OUT_JSON"
else
  echo "{}" > "$OUT_JSON".empty
  echo "NOTE: JSON vacío -> $OUT_JSON.empty"
fi

echo "OK: $OUT_TXT"
