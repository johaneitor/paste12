#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }

ts() { date -u +%Y%m%d-%H%M%SZ; }
TS="$(ts)"
TMP="${TMPDIR:-$HOME/tmp}/fe.$$"; mkdir -p "$TMP"

# --- localizar carpeta de auditorías previa (misma carpeta de "ayer") ---
cands=(
  "$HOME/Download" "$HOME/downloads"
  "/sdcard/Download" "/sdcard/Download/terabox"
  "/storage/emulated/0/Download" "/storage/emulated/0/Download/terabox"
)
find_prev_dir() {
  for d in "${cands[@]}"; do
    [ -d "$d" ] || continue
    f="$(ls -1t "$d"/audit-frontend-* "$d"/frontend-*-*.{md,txt,html} 2>/dev/null | head -n1 || true)"
    [ -n "${f:-}" ] && { dirname "$f"; return; }
  done
  # fallback razonables
  for d in "/sdcard/Download" "$HOME/Download" "$HOME/downloads"; do
    [ -d "$d" ] && echo "$d" && return
  done
  mkdir -p "$HOME/downloads"; echo "$HOME/downloads"
}
DEST="$(find_prev_dir)"
mkdir -p "$DEST"

RAW_HTML="$DEST/index-$(ts).html"
JS_MAN="$DEST/js-manifest-$(ts).txt"
OUT_TXT="$DEST/audit-frontend-$(ts).txt"
OUT_MD="$DEST/frontend-overview-$(ts).md"

say(){ echo -e "$*"; }

# --- 1) Descargar index (desactiva SW viejo si soporta ?nosw=1) ---
curl -fsS "$BASE/?_ts=$TS&nosw=1" -o "$TMP/index.html"
cp "$TMP/index.html" "$RAW_HTML"

BYTES="$(wc -c < "$TMP/index.html" | tr -d ' ')"
SCOUNT="$(grep -oi '<script[^>]*>' "$TMP/index.html" | wc -l | tr -d ' ')"

# --- 2) Extraer JS externos y bajar ---
mkdir -p "$TMP/js"
grep -oi '<script[^>]*src=[^>]*>' "$TMP/index.html" \
| sed -n 's/.*src=["'\'']\([^"'\''#? ]\+\).*/\1/p' \
| while read -r u; do
    case "$u" in http*|/*) full="$u";; *) full="$BASE/$u";; esac
    fn="$(echo "$u" | tr '/:?&=%' '__')"
    curl -fsS "$full" -o "$TMP/js/$fn" || true
  done
(ls -1 "$TMP/js" 2>/dev/null || true) > "$JS_MAN"

# --- 3) Scripts inline (para heurística) ---
INLINE="$TMP/inline.js"
awk 'BEGIN{RS="<script";FS="</script>"}NR>1{print "<script"$0}' "$TMP/index.html" > "$INLINE" || true

check_file(){
  local f="$1"
  [ -s "$f" ] || { echo "api_notes=0"; echo "uses_offset=0"; echo "uses_keyset=0"; echo "reads_xnext=0"; echo "uses_sw=0"; echo "has_like=0"; echo "has_report=0"; echo "has_share=0"; echo "has_load_more=0"; echo "submit_listeners=0"; echo "refs_text_required=0"; echo "has_update_banner=0"; return; }
  grep -q "fetch\s*(\s*['\"]/api/notes" "$f" 2>/dev/null && echo api_notes=1 || echo api_notes=0
  grep -q "/api/notes[^\"]*offset=" "$f" 2>/dev/null      && echo uses_offset=1 || echo uses_offset=0
  grep -q "cursor_ts" "$f" 2>/dev/null                    && echo uses_keyset=1 || echo uses_keyset=0
  grep -qi "X-Next-Cursor" "$f" 2>/dev/null               && echo reads_xnext=1 || echo reads_xnext=0
  grep -qi "serviceWorker" "$f" 2>/dev/null               && echo uses_sw=1 || echo uses_sw=0
  grep -Eqi "/api/notes/.+/(like|view|report)" "$f" 2>/dev/null && {
    grep -qi "/like" "$f" && echo has_like=1 || echo has_like=0
    grep -qi "/report" "$f" && echo has_report=1 || echo has_report=0
  } || { echo has_like=0; echo has_report=0; }
  grep -qi "share" "$f" 2>/dev/null && echo has_share=1 || echo has_share=0
  grep -qi "ver más|ver mas|load more" "$f" 2>/dev/null && echo has_load_more=1 || echo has_load_more=0
  grep -qi "addEventListener[[:space:]]*\([[:space:]]*['\"]submit" "$f" 2>/dev/null && echo submit_listeners=1 || echo submit_listeners=0
  grep -qi "text_required" "$f" 2>/dev/null               && echo refs_text_required=1 || echo refs_text_required=0
  grep -qi "nueva actualización disponible|update available" "$f" 2>/dev/null && echo has_update_banner=1 || echo has_update_banner=0
}
sum(){ awk -F= '{a[$1]+=$2} END{for(k in a)print k"="a[k]}' | sort; }

{ check_file "$INLINE"
  for f in "$TMP"/js/*; do [ -s "$f" ] && check_file "$f" || true; done;
} | sum > "$TMP/flags.txt"

DUP_SUBMIT="$(grep -iR "addEventListener[[:space:]]*\([[:space:]]*['\"]submit" "$INLINE" "$TMP"/js/* 2>/dev/null | wc -l | tr -d ' ')"

# --- 4) Escribir informes ---
{
  echo "== FETCH index.html =="
  echo "bytes: $BYTES"
  echo "scripts: $SCOUNT"
  echo
  echo "== Heurística =="
  cat "$TMP/flags.txt" 2>/dev/null || true
  echo
  echo "== Sospechas =="
  echo "- submit listeners duplicados: $DUP_SUBMIT (si >1, puede romper publicar)."
  echo "- usa offset y NO keyset: revisar paginación por Link/X-Next-Cursor."
  echo "- text_required referenciado: validar que el input name='text' exista y se envíe JSON correcto."
  echo "- service worker: si usa SW, probar con '?nosw=1' y limpiar caches."
} > "$OUT_TXT"

{
  echo "# Frontend Overview — $TS"
  echo
  echo "- Destino: **$DEST**"
  echo "- index bytes: **$BYTES**, scripts: **$SCOUNT**"
  echo
  echo "## Señales"
  sed 's/^/- /' "$TMP/flags.txt" 2>/dev/null || true
  echo
  echo "## Anomalías probables"
  echo "- Submit duplicado: **$DUP_SUBMIT**"
  echo "- Si *uses_offset>0* y *uses_keyset=0*: UI no entiende Link/X-Next-Cursor."
  echo "- Si *refs_text_required>0*: faltan checks de cliente (mín. longitud) o se manda body sin 'text'."
  echo "- Si *uses_sw>0*: SW puede inyectar banner/update — conviene apagar y limpiar."
  echo
  echo "## Archivos guardados"
  echo "- HTML: **$(basename "$RAW_HTML")**"
  echo "- JS manifest: **$(basename "$JS_MAN")**"
  echo "- TXT: **$(basename "$OUT_TXT")**"
} > "$OUT_MD"

echo "OK: auditoría en:"
echo "  $OUT_TXT"
echo "  $OUT_MD"
echo "  $RAW_HTML"
echo "  $JS_MAN"
