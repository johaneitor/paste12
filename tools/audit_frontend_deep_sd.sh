#!/usr/bin/env bash
set -euo pipefail

BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }

pick_dest() {
  for d in "/sdcard/Download" "/storage/emulated/0/Download" "$HOME/Download" "$HOME/downloads"; do
    if [ -d "$d" ] && [ -w "$d" ]; then echo "$d"; return; fi
  done
  mkdir -p "$HOME/downloads"; echo "$HOME/downloads"
}

DEST="$(pick_dest)"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
TMP="${TMPDIR:-/tmp}/feaudit.$$.d"
mkdir -p "$TMP"

OUT_HTML="$DEST/index-$TS.html"
OUT_JS_LIST="$DEST/js-manifest-$TS.txt"
OUT_SUM="$DEST/frontend-overview-$TS.md"

HTML="$TMP/index.html"
INLINE="$TMP/inline.js"
ASSET_DIR="$TMP/js"
mkdir -p "$ASSET_DIR"

say(){ echo -e "$*"; }
sep(){ echo "---------------------------------------------"; }

say "== FETCH index (sin SW) =="
# Guardamos directamente en sdcard (y copia de trabajo)
if curl -fsS "$BASE/?nosw=1&_=$TS" -o "$HTML"; then
  cp -f "$HTML" "$OUT_HTML"
else
  echo "<!-- fetch failed $TS -->" > "$OUT_HTML"
  echo "✗ no pude descargar index de $BASE" >&2
fi

BYTES="$(wc -c < "$HTML" 2>/dev/null | tr -d ' ' || echo 0)"
SCOUNT="$(grep -oi '<script[^>]*>' "$HTML" 2>/dev/null | wc -l | tr -d ' ' || echo 0)"
say "bytes: $BYTES"
say "scripts: $SCOUNT"
sep

say "== Extraer scripts externos e inline =="
# JS externos
grep -oi '<script[^>]*src=[^>]*>' "$HTML" 2>/dev/null \
| sed -n 's/.*src=["'\'']\([^"'\''#? ]\+\).*/\1/p' \
| while read -r u; do
    [ -n "$u" ] || continue
    case "$u" in http*|/*) full="$u";; *) full="$BASE/$u";; esac
    fn="$(echo "$u" | tr '/:?&=' '_')"
    curl -fsS "$full" -o "$ASSET_DIR/$fn" || true
  done
ls -1 "$ASSET_DIR" > "$OUT_JS_LIST" 2>/dev/null || true

# JS inline (naive extractor)
awk 'BEGIN{RS="<script";FS="</script>"}NR>1{print "<script"$0}' "$HTML" > "$INLINE" || true

# Señales por archivo
check_file(){
  local f="$1"; [ -s "$f" ] || { return 0; }
  grep -qE "fetch[[:space:]]*\([[:space:]]*['\"]/api/notes" "$f" && echo api_notes=1 || echo api_notes=0
  grep -qE "/api/notes[^\"']*offset=" "$f"             && echo uses_offset=1 || echo uses_offset=0
  (grep -q "cursor_ts" "$f" || grep -q "cursor_id" "$f") && echo uses_keyset=1 || echo uses_keyset=0
  grep -qi "X-Next-Cursor" "$f"                        && echo reads_xnext=1 || echo reads_xnext=0
  grep -qE '\blink\b' "$f"                             && echo reads_link=1 || echo reads_link=0

  grep -qE "/api/notes/[^\"']+/like" "$f"              && echo has_like=1 || echo has_like=0
  grep -qE "/api/notes/[^\"']+/view" "$f"              && echo has_view=1 || echo has_view=0
  grep -qE "/api/notes/[^\"']+/report" "$f"            && echo has_report=1 || echo has_report=0

  grep -qi "Content-Type['\"]:[[:space:]]*['\"]application/json" "$f" && echo publish_json=1 || echo publish_json=0
  (grep -qi "application/x-www-form-urlencoded" "$f" || grep -q "FormData" "$f") && echo publish_form=1 || echo publish_form=0
  grep -qi "text_required" "$f"                        && echo refs_text_required=1 || echo refs_text_required=0
  grep -qi "addEventListener[[:space:]]*\([[:space:]]*['\"]submit" "$f" && echo submit_listener=1 || echo submit_listener=0

  grep -qi "serviceWorker" "$f"                        && echo uses_sw=1 || echo uses_sw=0
  grep -qi "navigator\.share" "$f"                     && echo uses_webshare=1 || echo uses_webshare=0
  grep -qi "IntersectionObserver" "$f"                 && echo uses_io=1 || echo uses_io=0

  grep -qi 'name="p12-safe-shim"\|id="p12-cohesion-v7"\|name="p12-v7"' "$f" && echo has_p12_marker=1 || echo has_p12_marker=0
  (grep -qi 'name="p12-single"' "$f" || grep -qi 'data-single=' "$f") && echo has_single=1 || echo has_single=0
}

sum_flags(){ awk -F= '{a[$1]+=$2} END{for(k in a)print k"="a[k]}' | sort; }

# Acumular señales
{
  check_file "$HTML"
  check_file "$INLINE"
  for f in "$ASSET_DIR"/*; do [ -s "$f" ] && check_file "$f" || true; done
} | sum_flags > "$TMP/flags.txt" || true

DUP_SUBMIT="$(grep -iR "addEventListener[[:space:]]*\([[:space:]]*['\"]submit" "$INLINE" "$ASSET_DIR"/* 2>/dev/null | wc -l | tr -d ' ' || echo 0)"

# Informe
{
  echo "# Frontend Audit — $TS"
  echo
  echo "## Archivos"
  echo "- HTML guardado: **$(basename "$OUT_HTML")**"
  echo "- JS manifest: **$(basename "$OUT_JS_LIST")**"
  echo "- Carpeta destino: **$DEST**"
  echo
  echo "## Métricas"
  echo "- Bytes index: **$BYTES**"
  echo "- Cantidad de <script>: **$SCOUNT**"
  echo
  echo "## Señales detectadas"
  if [ -s "$TMP/flags.txt" ]; then sed 's/^/- /' "$TMP/flags.txt"; else echo "- (sin señales)"; fi
  echo
  echo "## Anomalías probables"
  if [ "${BYTES:-0}" = "0" ]; then
    echo "- **bytes=0** → el index se está sirviendo vacío. Revisar el _finish/guard del WSGI y la ruta de index."
  fi
  echo "- **submit_listener>1** → listeners duplicados pueden romper publish/paginación. Detectados: $DUP_SUBMIT."
  echo "- **uses_offset>0 & uses_keyset=0** → la UI usa offset y no entiende keyset (Link/X-Next-Cursor)."
  echo "- **refs_text_required>0 & publish_json=1 & publish_form=0** → falta fallback FORM → 400 \"text_required\"."
  echo "- **uses_sw=1** → un SW viejo puede servir assets rotos; probar con **?nosw=1** y considerar unregister."
  echo
  echo "## Recomendaciones rápidas"
  echo "1) Mantener publish con **fallback FORM** si JSON falla (400)."
  echo "2) Paginación: implementar **keyset** leyendo **X-Next-Cursor** o **Link**."
  echo "3) Unificar handlers de like/view/report con **event delegation** en el contenedor del feed."
  echo "4) Soportar **?nosw=1** → desregistrar Service Worker viejo para evitar cache fantasma."
  echo "5) Nota única: admitir **data-single** en <body> o parseo de **?id=NNN** en el frontend."
} > "$OUT_SUM"

sep
echo "OK: $OUT_SUM"
echo "OK: $OUT_HTML"
echo "OK: $OUT_JS_LIST"
