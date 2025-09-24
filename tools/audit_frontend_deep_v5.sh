#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }
TS="$(date -u +%Y%m%d-%H%M%SZ)"
TMP="${TMPDIR:-/tmp}/fe.$$"; mkdir -p "$TMP"
OUT="$HOME/downloads/frontend-overview-$TS.md"
RAW="$HOME/downloads/index-$TS.html"
JSOUT="$HOME/downloads/js-manifest-$TS.txt"

say(){ echo -e "$*"; }

# 1) Descarga index
curl -fsS "$BASE/?_=$TS" -o "$TMP/index.html"
cp "$TMP/index.html" "$RAW"
BYTES="$(wc -c < "$TMP/index.html" | tr -d ' ')"
SCOUNT="$(grep -oi '<script[^>]*>' "$TMP/index.html" | wc -l | tr -d ' ')"

# 2) Extrae scripts externos y los baja para análisis
mkdir -p "$TMP/js"
grep -oi '<script[^>]*src=[^>]*>' "$TMP/index.html" | \
sed -n 's/.*src=["'\'']\([^"'\''#? ]\+\).*/\1/p' | while read -r u; do
  case "$u" in http*|/*) full="$u";; *) full="$BASE/$u";; esac
  fn="$(echo "$u" | tr '/:?&=' '_')"
  curl -fsS "$full" -o "$TMP/js/$fn" || true
done
ls -1 "$TMP/js" > "$JSOUT" 2>/dev/null || true

# 3) Vuelca scripts inline
INLINE="$TMP/inline.js"
awk 'BEGIN{RS="<script";FS="</script>"}NR>1{print "<script"$0}' "$TMP/index.html" > "$INLINE"

# 4) Heurísticas
check_file(){
  local f="$1"
  grep -q "fetch\s*(\s*['\"]/api/notes" "$f" 2>/dev/null && echo api_notes=1 || echo api_notes=0
  grep -q "/api/notes[^\"]*offset=" "$f" 2>/dev/null && echo uses_offset=1 || echo uses_offset=0
  grep -q "cursor_ts" "$f" 2>/dev/null && echo uses_keyset=1 || echo uses_keyset=0
  grep -q -i "Link" "$f" 2>/dev/null && echo reads_link=1 || echo reads_link=0
  grep -qi "serviceWorker" "$f" 2>/dev/null && echo uses_sw=1 || echo uses_sw=0
  grep -q "/api/notes/[^\"]\+/like" "$f" 2>/dev/null && echo has_like=1 || echo has_like=0
  grep -q "/api/notes/[^\"]\+/report" "$f" 2>/dev/null && echo has_report=1 || echo has_report=0
  grep -qi "ver más\|ver mas" "$f" 2>/dev/null && echo has_ver=1 || echo has_ver=0
  grep -qi "addEventListener\\s*\\(\\s*['\"]submit" "$f" 2>/dev/null && echo has_submit_listener=1 || echo has_submit_listener=0
  grep -qi "text_required" "$f" 2>/dev/null && echo refs_text_required=1 || echo refs_text_required=0
}

sum(){ awk -F= '{a[$1]+=$2} END{for(k in a)print k"="a[k]}' | sort; }

{ check_file "$INLINE"
  for f in "$TMP"/js/*; do [ -s "$f" ] && check_file "$f" || true; done; } \
| sum > "$TMP/flags.txt"

# 5) Posibles duplicados (dos o más listeners submit)
DUP_SUBMIT="$(grep -iR "addEventListener\s*(\s*['\"]submit" "$INLINE" "$TMP"/js/* 2>/dev/null | wc -l | tr -d ' ')"

# 6) Reporte
{
  echo "# Frontend Deep Overview — $TS"
  echo
  echo "- index bytes: **$BYTES**"
  echo "- <script> tags: **$SCOUNT**"
  echo "- JS externos descargados: **$(ls -1 "$TMP/js" 2>/dev/null | wc -l | tr -d ' ')**"
  echo
  echo "## Heurísticas agregadas"
  sed 's/^/- /' "$TMP/flags.txt" 2>/dev/null || true
  echo
  echo "## Posibles problemas"
  echo "- Múltiples listeners de \`submit\`: **$DUP_SUBMIT**"
  echo "- Si \`uses_offset>0\` y \`uses_keyset=0\`: UI desactualizado para paginación."
  echo "- Si \`refs_text_required>0\`: sin validación cliente → 400."
  echo "- Si \`uses_sw>0\`: fuerza \`?nosw=1\` para evitar SW viejo."
  echo
  echo "## Archivos generados"
  echo "- HTML original: **$(basename "$RAW")**"
  echo "- JS manifest: **$(basename "$JSOUT")**"
} > "$OUT"

echo "OK: resumen en $OUT"
echo "HTML en $RAW"
echo "JS manifest en $JSOUT"
