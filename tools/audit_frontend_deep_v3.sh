#!/usr/bin/env bash
set -euo pipefail

BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }
ORIGIN="$(echo "$BASE" | sed -E 's#^(https?://[^/]+).*$#\1#')"
TS="$(date -u +%Y%m%d-%H%M%SZ)"

# Destino en almacenamiento interno (Android) o fallback a ~/downloads
DEST_DIR="${DEST_DIR_OVERRIDE:-/storage/emulated/0/Download}"
[ -d "$DEST_DIR" ] || DEST_DIR="$HOME/downloads"
mkdir -p "$DEST_DIR"

WORK="${TMPDIR:-$HOME/tmp}/feaudit.$$.work"
mkdir -p "$WORK/assets" "$WORK/headers"
REPORT="$DEST_DIR/audit-frontend-${TS}.txt"
BUNDLE="$DEST_DIR/audit-frontend-${TS}.tar.gz"

say(){ printf "%s\n" "$*" | tee -a "$REPORT" >/dev/null; }
sep(){ say "---------------------------------------------"; }

# -------- Fetch index.html ----------
say "== FETCH index.html =="
curl -fsSL --compressed -D "$WORK/headers/index.h" "$BASE/" -o "$WORK/index.html" || {
  say "✗ no pude descargar index.html"; exit 3; }
BYTES="$(wc -c < "$WORK/index.html" | tr -d ' ')"
say "bytes: $BYTES"
CT="$(grep -i '^content-type:' "$WORK/headers/index.h" | head -n1 | cut -d' ' -f2-)"
say "content-type: ${CT:-desconocido}"
sep

# -------- Asset discovery ----------
say "== Assets JS detectados =="
# Captura src="...js" y type=module también
ASSETS=$(awk '
  BEGIN{IGNORECASE=1}
  {
    while (match($0,/(<script[^>]*src=)["'\''"]?([^"'\'' >]+\.js[^"'\'' >]*)["'\''"]?[^>]*>/,m)) {
      print m[2]; $0=substr($0, RSTART+RLENGTH)
    }
  }' "$WORK/index.html" | sort -u)

N_ASSETS=0
echo "$ASSETS" | while read -r u; do
  [ -n "$u" ] || continue
  N_ASSETS=$((N_ASSETS+1))
  echo " - $u"
done | tee -a "$REPORT" >/dev/null
[ "${N_ASSETS:-0}" -eq 0 ] && say "scripts: 0"
sep

# -------- Download assets ----------
say "== Descarga y escaneo de JS =="
> "$WORK/scan.txt"
resolve_url(){
  local u="$1"
  case "$u" in
    http://*|https://*) echo "$u" ;;
    /*) echo "${ORIGIN}${u}" ;;
    *)  # relativo
        # BASE/ -> recorta hasta ruta
        echo "${BASE%/}/$u" ;;
  esac
}
dl_asset(){
  local raw="$1"; local url; url="$(resolve_url "$raw")"
  local fname; fname="$(echo "$raw" | sed 's#[^A-Za-z0-9._-]#_#g')"
  curl -fsSL --compressed -D "$WORK/headers/$fname.h" "$url" -o "$WORK/assets/$fname" || return 1
  echo "$fname"
}
echo "$ASSETS" | while read -r a; do
  [ -n "$a" ] || continue
  fname="$(dl_asset "$a" || true)"
  if [ -n "$fname" ] && [ -s "$WORK/assets/$fname" ]; then
    echo "• $a -> assets/$fname" | tee -a "$REPORT" >/dev/null
  else
    echo "• $a -> (falló descarga)" | tee -a "$REPORT" >/dev/null
  fi
done
sep

# -------- Pattern scan (HTML + JS) ----------
say "== Heurística de compatibilidad =="

scan_file(){ local f="$1"
  awk 'BEGIN{IGNORECASE=1}
       {print}' "$f"
}

merge_to_scan(){
  cat "$WORK/index.html" > "$WORK/SCAN_ALL.txt"
  for f in "$WORK"/assets/*; do [ -f "$f" ] && printf "\n/*--- %s ---*/\n" "$(basename "$f")" >> "$WORK/SCAN_ALL.txt" && cat "$f" >> "$WORK/SCAN_ALL.txt"; done
}
merge_to_scan

check(){
  local label="$1" rx="$2"
  if grep -qiE "$rx" "$WORK/SCAN_ALL.txt"; then
    say "• $label: sí"
    return 0
  else
    say "• $label: no"
    return 1
  fi
}

# SW / Workbox / caches
check "serviceWorker.register" "serviceWorker\.register|navigator\.serviceWorker"
check "Workbox" "__WB_MANIFEST|workbox"
check "caches API" "caches\.open|cacheStorage"

# Mensajes UI
check "banner 'nueva versión disponible'" "nueva versi[oó]n disponible|update available|refresh for the latest|hay una nueva versi[oó]n"
check "mensaje 'no se puede enviar'" "no se puede enviar|no se pudo enviar|failed to send"

# Publicación
HAS_PUB_JSON=0; grep -qiE 'fetch\(.?/api/notes[",][^)]*{[^}]*method\s*:\s*["'\'']POST' "$WORK/SCAN_ALL.txt" && HAS_PUB_JSON=1
say "• publish via fetch JSON: $([ $HAS_PUB_JSON -eq 1 ] && echo sí || echo no)"

# Paginación
USES_OFFSET=0; grep -qiE '([?&]offset=|page=)' "$WORK/SCAN_ALL.txt" && USES_OFFSET=1
USES_KEYSET=0; grep -qiE '(cursor_ts|cursor_id|X-Next-Cursor|Link.*rel="?next"?)' "$WORK/SCAN_ALL.txt" && USES_KEYSET=1
say "• paginación con offset=: $([ $USES_OFFSET -eq 1 ] && echo sí || echo no)"
say "• paginación keyset (cursor_ts/cursor_id): $([ $USES_KEYSET -eq 1 ] && echo sí || echo no)"

# Detección básica de acciones (like/report/share) en renderizadores
HAS_ACTIONS=0; grep -qiE '(like|❤️|report|🚩|compartir|share)' "$WORK/SCAN_ALL.txt" && HAS_ACTIONS=1
say "• acciones (like/report/share) en plantilla o JS: $([ $HAS_ACTIONS -eq 1 ] && echo sí || echo no)"

sep

# -------- API contract quick check (no muta) ----------
say "== Contrato API (no destrutivo) =="
HSTAT="$(curl -fsSi "$BASE/api/health" -o "$WORK/health.json" -w '%{http_code}\n' | sed -n '1p')"
say "• /api/health: HTTP/$HSTAT"
if command -v jq >/dev/null 2>&1; then jq -r '.' < "$WORK/health.json" | head -n 1 | tee -a "$REPORT" >/dev/null; else head -n 1 "$WORK/health.json" | tee -a "$REPORT" >/dev/null; fi

curl -fsS --compressed -D "$WORK/headers/notes.h" "$BASE/api/notes?limit=5" -o "$WORK/notes.json" >/dev/null || true
STATUS_LINE="$(sed -n '1p' "$WORK/headers/notes.h")"
say "• GET /api/notes?limit=5: $STATUS_LINE"
LINK_NEXT="$(grep -i '^Link:' "$WORK/headers/notes.h" | sed -n 's/^[Ll]ink:\s*<\([^>]*\)>;.*$/\1/p' | head -n1)"
XNEXT="$(grep -i '^X-Next-Cursor:' "$WORK/headers/notes.h" | cut -d' ' -f2- | head -n1)"
[ -n "$LINK_NEXT" ] && say "  - Link next: $LINK_NEXT" || say "  - Link next: (no)"
[ -n "$XNEXT" ]     && say "  - X-Next-Cursor: $XNEXT" || say "  - X-Next-Cursor: (no)"
if command -v jq >/dev/null 2>&1; then
  CNT="$(jq -r '.items|length' < "$WORK/notes.json" 2>/dev/null || echo 0)"
  FIRST_ID="$(jq -r '.items[0].id // empty' < "$WORK/notes.json" 2>/dev/null || true)"
  say "  - items: ${CNT:-0} (primero: ${FIRST_ID:-n/a})"
else
  say "  - items: (instala jq para más detalle)"
fi

curl -fsS --compressed -D "$WORK/headers/stamp.h" "$BASE/api/deploy-stamp" -o "$WORK/stamp.json" >/dev/null || true
STAMP_STATUS="$(sed -n '1p' "$WORK/headers/stamp.h")"
say "• /api/deploy-stamp: $STAMP_STATUS"
if command -v jq >/dev/null 2>&1; then
  jq -r '{commit: (.deploy.commit // .commit // ""), date: (.deploy.date // .date // "")}' < "$WORK/stamp.json" 2>/dev/null | tee -a "$REPORT" >/dev/null
else
  head -n 1 "$WORK/stamp.json" | tee -a "$REPORT" >/dev/null
fi
sep

# -------- Findings (diagnóstico guiado) ----------
say "== Hallazgos y señales =="

if grep -qiE 'no se puede enviar|no se pudo enviar|failed to send' "$WORK/SCAN_ALL.txt"; then
  say "• Se detectó mensaje de error de envío en el frontend."
  say "  Probable causa: handler JS intercepta submit/click sin fallback cuando el fetch falla."
fi

if grep -qiE 'serviceWorker\.register|__WB_MANIFEST|workbox' "$WORK/SCAN_ALL.txt"; then
  say "• Se detectó Service Worker/Workbox; puede mostrar banner 'Nueva versión disponible' y cachear assets."
  say "  Recomendación: desregistrar SW o incluir lógica de autoupdate sin banner intrusivo."
fi

if [ "$USES_KEYSET" -eq 0 ]; then
  say "• El frontend NO parece leer 'Link: rel=\"next\"' ni 'X-Next-Cursor'."
  say "  Resultado: 'Cargar más' podría no paginar o repetir/hacer offset incorrecto."
fi

if [ "$HAS_ACTIONS" -eq 0 ]; then
  say "• No se localizaron claramente acciones (like/report/share) en el render de items."
  say "  Resultado: las notas cargadas vía paginación podrían carecer de botones."
fi

sep

# -------- Recomendaciones (seguras y reversibles) ----------
say "== Recomendaciones (seguras y reversibles) =="
say "1) Publicar con fallback: si el fetch POST /api/notes falla, NO hacer preventDefault; dejar submit nativo."
say "2) Paginación: leer Link rel=next o X-Next-Cursor; añadir botón 'Cargar más' que consuma esa URL."
say "3) Acciones: al clonar/crear card, inyectar like/report/share si el template no las trae."
say "4) SW/Banner: desregistrar SW y suprimir el toast de 'nueva versión disponible' (o auto-actualizar silencioso)."
say ""
say "Siguiente paso sugerido: te preparo un parche PE 'no intrusivo' y REVERSIBLE tras revisar este informe."
sep

# -------- Bundle para revisión offline ----------
tar -C "$WORK" -czf "$BUNDLE" .
say "Artefactos:"
say "• Reporte: $REPORT"
say "• Bundle:  $BUNDLE"
echo "Listo: $REPORT"
