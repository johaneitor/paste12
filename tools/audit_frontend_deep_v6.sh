#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }

# Detecta carpeta Download del teléfono (Termux/Android)
pick_dest() {
  for d in "$HOME/Download" "$HOME/downloads" "/sdcard/Download" "/storage/emulated/0/Download"; do
    if [ -d "$d" ] && [ -w "$d" ]; then echo "$d"; return; fi
  done
  mkdir -p "$HOME/downloads"; echo "$HOME/downloads"
}
DEST="$(pick_dest)"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
TMP="${TMPDIR:-/tmp}/fe.$$"; mkdir -p "$TMP"

RAW_HTML="$DEST/index-$TS.html"
JS_LIST="$DEST/js-manifest-$TS.txt"
OUT_SUM="$DEST/frontend-overview-$TS.md"

say(){ echo -e "$*"; }

# 1) Descargar index
curl -fsS "$BASE/?_=$TS" -o "$TMP/index.html"
cp "$TMP/index.html" "$RAW_HTML"
BYTES="$(wc -c < "$TMP/index.html" | tr -d ' ')"
SCOUNT="$(grep -oi '<script[^>]*>' "$TMP/index.html" | wc -l | tr -d ' ')"

# 2) Extraer JS externos y bajar
mkdir -p "$TMP/js"
grep -oi '<script[^>]*src=[^>]*>' "$TMP/index.html" \
| sed -n 's/.*src=["'\'']\([^"'\''#? ]\+\).*/\1/p' \
| while read -r u; do
    case "$u" in http*|/*) full="$u";; *) full="$BASE/$u";; esac
    fn="$(echo "$u" | tr '/:?&=' '_')"
    curl -fsS "$full" -o "$TMP/js/$fn" || true
  done
ls -1 "$TMP/js" > "$JS_LIST" 2>/dev/null || true

# 3) Scripts inline
INLINE="$TMP/inline.js"
awk 'BEGIN{RS="<script";FS="</script>"}NR>1{print "<script"$0}' "$TMP/index.html" > "$INLINE" || true

check_file(){
  local f="$1"
  grep -q "fetch\s*(\s*['\"]/api/notes" "$f" 2>/dev/null && echo api_notes=1 || echo api_notes=0
  grep -q "/api/notes[^\"]*offset=" "$f" 2>/dev/null      && echo uses_offset=1 || echo uses_offset=0
  grep -q "cursor_ts" "$f" 2>/dev/null                    && echo uses_keyset=1 || echo uses_keyset=0
  grep -qi "serviceWorker" "$f" 2>/dev/null               && echo uses_sw=1 || echo uses_sw=0
  grep -q "/api/notes/[^\"]\+/like" "$f" 2>/dev/null      && echo has_like=1 || echo has_like=0
  grep -q "/api/notes/[^\"]\+/report" "$f" 2>/dev/null    && echo has_report=1 || echo has_report=0
  grep -qi "ver más\|ver mas" "$f" 2>/dev/null            && echo has_ver=1 || echo has_ver=0
  grep -qi "addEventListener\\s*\\(\\s*['\"]submit" "$f" 2>/dev/null && echo submit_listeners=1 || echo submit_listeners=0
  grep -qi "text_required" "$f" 2>/dev/null               && echo refs_text_required=1 || echo refs_text_required=0
}
sum(){ awk -F= '{a[$1]+=$2} END{for(k in a)print k"="a[k]}' | sort; }

{ check_file "$INLINE"
  for f in "$TMP"/js/*; do [ -s "$f" ] && check_file "$f" || true; done; } \
| sum > "$TMP/flags.txt"

DUP_SUBMIT="$(grep -iR "addEventListener\s*(\s*['\"]submit" "$INLINE" "$TMP"/js/* 2>/dev/null | wc -l | tr -d ' ')"

{
  echo "# Frontend Overview — $TS"
  echo
  echo "- Destino de archivos: **$DEST**"
  echo "- index bytes: **$BYTES**"
  echo "- <script> tags: **$SCOUNT**"
  echo "- JS externos descargados: **$(ls -1 "$TMP/js" 2>/dev/null | wc -l | tr -d ' ')**"
  echo
  echo "## Señales detectadas"
  sed 's/^/- /' "$TMP/flags.txt" 2>/dev/null || true
  echo
  echo "## Anomalías probables"
  echo "- Listeners de submit duplicados: **$DUP_SUBMIT** (si >1, puede interferir con publicar/paginación)."
  echo "- Si hay *uses_offset>0* y *uses_keyset=0*: la UI usa offset y no entiende Link/X-Next-Cursor."
  echo "- Si *refs_text_required>0*: falta validación cliente → 400 al publicar."
  echo "- Si *uses_sw>0*: un SW viejo puede romper UI; probar con \`?nosw=1\`."
  echo
  echo "## Archivos guardados"
  echo "- HTML: **$(basename "$RAW_HTML")**"
  echo "- Manifest JS: **$(basename "$JS_LIST")**"
} > "$OUT_SUM"

echo "OK: resumen -> $OUT_SUM"
echo "HTML -> $RAW_HTML"
echo "JS manifest -> $JS_LIST"
