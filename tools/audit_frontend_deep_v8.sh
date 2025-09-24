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
TMP="${TMPDIR:-/tmp}/feaudit.$$.tmp"; mkdir -p "$TMP"
HTML="$TMP/index.html"
INLINE="$TMP/inline.js"
ASSET_DIR="$TMP/js"
OUT_SUM="$DEST/frontend-overview-$TS.md"
OUT_HTML="$DEST/index-$TS.html"
OUT_JS_LIST="$DEST/js-manifest-$TS.txt"

say(){ echo -e "$*"; }
sep(){ echo "---------------------------------------------"; }

say "== FETCH index (sin SW) =="
curl -fsS "$BASE/?nosw=1&_=$TS" -o "$HTML" || { echo "✗ no pude descargar index"; exit 1; }
cp -f "$HTML" "$OUT_HTML"

BYTES="$(wc -c < "$HTML" | tr -d ' ')"
SCOUNT="$(grep -oi '<script[^>]*>' "$HTML" | wc -l | tr -d ' ')"
say "bytes: $BYTES"
say "scripts: $SCOUNT"
sep

say "== Extraer scripts externos e inline =="
mkdir -p "$ASSET_DIR"
grep -oi '<script[^>]*src=[^>]*>' "$HTML" \
| sed -n 's/.*src=["'\'']\([^"'\''#? ]\+\).*/\1/p' \
| while read -r u; do
    case "$u" in http*|/*) full="$u";; *) full="$BASE/$u";; esac
    fn="$(echo "$u" | tr '/:?&=' '_')"
    curl -fsS "$full" -o "$ASSET_DIR/$fn" || true
  done
ls -1 "$ASSET_DIR" > "$OUT_JS_LIST" 2>/dev/null || true

# Inline JS (naive extractor)
awk 'BEGIN{RS="<script";FS="</script>"}NR>1{print "<script"$0}' "$HTML" > "$INLINE" || true

# Señales (función auxiliar por archivo)
check_file(){
  local f="$1"
  # API
  grep -q "fetch\s*(\s*['\"]/api/notes" "$f" 2>/dev/null && echo api_notes=1 || echo api_notes=0
  grep -q "/api/notes[^\"]*offset=" "$f" 2>/dev/null      && echo uses_offset=1 || echo uses_offset=0
  (grep -q "cursor_ts" "$f" 2>/dev/null || grep -q "cursor_id" "$f" 2>/dev/null) && echo uses_keyset=1 || echo uses_keyset=0
  grep -qi "X-Next-Cursor" "$f" 2>/dev/null              && echo reads_xnext=1 || echo reads_xnext=0
  grep -qi "Link" "$f" 2>/dev/null                       && echo reads_link=1 || echo reads_link=0

  # Interacciones
  grep -q "/api/notes/[^\"]\+/like" "$f" 2>/dev/null     && echo has_like=1 || echo has_like=0
  grep -q "/api/notes/[^\"]\+/view" "$f" 2>/dev/null     && echo has_view=1 || echo has_view=0
  grep -q "/api/notes/[^\"]\+/report" "$f" 2>/dev/null   && echo has_report=1 || echo has_report=0
  grep -qi "ver más\|ver mas" "$f" 2>/dev/null           && echo has_see_more=1 || echo has_see_more=0

  # Publish
  grep -qi "Content-Type['\"]:\s*['\"]application/json" "$f" 2>/dev/null && echo publish_json=1 || echo publish_json=0
  grep -qi "application\/x-www-form-urlencoded\|FormData" "$f" 2>/dev/null && echo publish_form=1 || echo publish_form=0
  grep -qi "text_required" "$f" 2>/dev/null              && echo refs_text_required=1 || echo refs_text_required=0
  grep -qi "addEventListener[[:space:]]*\([[:space:]]*['\"]submit" "$f" 2>/dev/null && echo submit_listener=1 || echo submit_listener=0

  # SW + compat
  grep -qi "serviceWorker" "$f" 2>/dev/null              && echo uses_sw=1 || echo uses_sw=0
  grep -qi "navigator\.share" "$f" 2>/dev/null           && echo uses_webshare=1 || echo uses_webshare=0
  grep -qi "IntersectionObserver" "$f" 2>/dev/null       && echo uses_io=1 || echo uses_io=0

  # Marcadores / single
  grep -qi 'name="p12-safe-shim"\|id="p12-cohesion-v7"\|name="p12-v7"' "$f" 2>/dev/null && echo has_p12_marker=1 || echo has_p12_marker=0
  grep -qi 'name="p12-single"\|data-single=' "$f" 2>/dev/null && echo has_single=1 || echo has_single=0
}

sum_flags(){ awk -F= '{a[$1]+=$2} END{for(k in a)print k"="a[k]}' | sort; }

# Acumular señales
{
  check_file "$HTML"
  check_file "$INLINE"
  for f in "$ASSET_DIR"/*; do [ -s "$f" ] && check_file "$f" || true; done
} | sum_flags > "$TMP/flags.txt"

# Heurísticas adicionales
DUP_SUBMIT="$(grep -iR "addEventListener[[:space:]]*\([[:space:]]*['\"]submit" "$INLINE" "$ASSET_DIR"/* 2>/dev/null | wc -l | tr -d ' ')"

# Construir resumen
{
  echo "# Frontend Audit — $TS"
  echo
  echo "## Archivos"
  echo "- HTML guardado: **$(basename "$OUT_HTML")**"
  echo "- JS manifest: **$(basename "$OUT_JS_LIST")**"
  echo
  echo "## Métricas"
  echo "- Bytes index: **$BYTES**"
  echo "- Cantidad de <script>: **$SCOUNT**"
  echo
  echo "## Señales detectadas"
  [ -s "$TMP/flags.txt" ] && sed 's/^/- /' "$TMP/flags.txt" || echo "- (sin señales)"
  echo
  echo "## Anomalías probables"
  echo "- **bytes=0** → index se está sirviendo vacío (revisar WSGI _finish y guard de index)."
  echo "- **submit_listener>1** → listeners duplicados pueden romper publish/paginación. Detectados: $DUP_SUBMIT."
  echo "- **uses_offset>0 & uses_keyset=0** → UI usa offset y no entiende keyset (Link/X-Next-Cursor)."
  echo "- **refs_text_required>0 & publish_json=1** → falta fallback FORM → 400 \"text_required\"."
  echo "- **uses_sw=1** → SW viejo puede servir assets rotos; probar con **?nosw=1** y considerar unregister."
  echo
  echo "## Recomendaciones rápidas"
  echo "1. Mantener publish con **fallback FORM** si JSON falla (400)."
  echo "2. Para paginación, preferir **keyset** (leer **X-Next-Cursor** o **Link**)."
  echo "3. Unificar handlers de like/view/report vía **event delegation** en el contenedor de notas."
  echo "4. Desregistrar SW viejo cuando se pase **?nosw=1**."
  echo "5. Para nota única, admitir **data-single** en <body> o **?id=NNN**."
  echo
  echo "_Destino de archivos_: $DEST"
} > "$OUT_SUM"

sep
say "OK: resumen -> $OUT_SUM"
say "HTML -> $OUT_HTML"
say "JS manifest -> $OUT_JS_LIST"
