#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }
TS="$(date -u +%Y%m%d-%H%M%SZ)"
TMP="${TMPDIR:-/tmp}/fe.$$"; mkdir -p "$TMP"
OUT="$HOME/downloads/frontend-overview-$TS.md"
RAW="$HOME/downloads/index-$TS.html"

say(){ echo -e "$*"; }

# --- Fetch index ---
curl -fsS "$BASE/?_=$TS" -o "$TMP/index.html"
cp "$TMP/index.html" "$RAW"
BYTES="$(wc -c < "$TMP/index.html" | tr -d ' ')"
SCOUNT="$(grep -oi '<script[^>]*>' "$TMP/index.html" | wc -l | tr -d ' ')"

# --- Extract external scripts and download them (best effort) ---
mkdir -p "$TMP/js"
grep -oi '<script[^>]*src=[^>]*>' "$TMP/index.html" | \
sed -n 's/.*src=["'\'']\([^"'\''#? ]\+\).*/\1/p' | while read -r u; do
  case "$u" in http*|/*) full="$u";; *) full="$BASE/$u";; esac
  fn="$(echo "$u" | tr '/:?&=' '_')"
  curl -fsS "$full" -o "$TMP/js/$fn" || true
done

# --- Heurísticas de compatibilidad ---
checks(){
  local f="$1"
  grep -q "fetch\s*(\s*['\"]/api/notes" "$f" 2>/dev/null && echo "api_notes=1" || echo "api_notes=0"
  grep -q "/api/notes[^\"]*offset=" "$f" 2>/dev/null && echo "uses_offset=1" || echo "uses_offset=0"
  grep -q "cursor_ts" "$f" 2>/dev/null && echo "uses_keyset=1" || echo "uses_keyset=0"
  grep -q "Link" "$f" 2>/dev/null && echo "reads_link=1" || echo "reads_link=0"
  grep -qi "serviceWorker" "$f" 2>/dev/null && echo "uses_sw=1" || echo "uses_sw=0"
  grep -q "/api/notes/[^\"]\+/like" "$f" 2>/dev/null && echo "has_like=1" || echo "has_like=0"
  grep -q "/api/notes/[^\"]\+/report" "$f" 2>/dev/null && echo "has_report=1" || echo "has_report=0"
  grep -qi "ver más" "$f" 2>/dev/null && echo "has_ver_mas_txt=1" || echo "has_ver_mas_txt=0"
}
INLINE="$(mktemp)"
# dump inline scripts
awk 'BEGIN{RS="<script";FS="</script>"}NR>1{print "<script"$0}' "$TMP/index.html" > "$INLINE"

# aggregate results
api_notes=0; uses_offset=0; uses_keyset=0; reads_link=0; uses_sw=0; has_like=0; has_report=0; has_ver=0
for f in "$INLINE" "$TMP"/js/*; do
  [ -s "$f" ] || continue
  eval "$(checks "$f")"
  (( api_notes+=$api_notes ))
  (( uses_offset+=$uses_offset ))
  (( uses_keyset+=$uses_keyset ))
  (( reads_link+=$reads_link ))
  (( uses_sw+=$uses_sw ))
  (( has_like+=$has_like ))
  (( has_report+=$has_report ))
  (( has_ver+=$has_ver_mas_txt ))
done

# posibles trampas
dup_submit="$(grep -iR "addEventListener\s*(\s*['\"]submit" "$INLINE" "$TMP"/js/* 2>/dev/null | wc -l | tr -d ' ')"
text_required_guard="$(grep -iR "text_required" "$INLINE" "$TMP"/js/* 2>/dev/null | wc -l | tr -d ' ')"

# --- Escribir resumen ---
cat > "$OUT" <<MD
# Frontend Overview — $TS

- index bytes: **$BYTES**
- <script> tags totales: **$SCOUNT**
- Archivos JS externos descargados: **$(ls -1 "$TMP/js" 2>/dev/null | wc -l | tr -d ' ')**

## Señales encontradas
- Llama a \`/api/notes\`: **$api_notes**
- Paginación *offset*: **$uses_offset**
- Paginación *keyset* (cursor\_ts / cursor\_id): **$uses_keyset**
- Lee cabecera \`Link:\`: **$reads_link**
- Service Worker: **$uses_sw**
- Endpoints like/report: **$has_like** / **$has_report**
- Texto "Ver más": **$has_ver**

## Posibles causas de fallas
- Múltiples listeners de \`submit\`: **$dup_submit**
- Referencias a \`text_required\` del backend (UI sin fallback): **$text_required_guard**

## Archivos generados
- HTML original: **$(basename "$RAW")**
- Este informe: **$(basename "$OUT")**

> Consejo: si \`uses_sw > 0\` probá agregar \`?nosw=1\` o hacer un refresh duro para evitar SW viejo.
MD

echo "OK: resumen en $OUT"
echo "HTML copiado a $RAW"
