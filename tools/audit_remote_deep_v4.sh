#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR] }"
OUTDIR="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
ROOT="$OUTDIR/paste12-remote-deep-$TS"
SUMMARY="$OUTDIR/paste12-remote-deep-$TS.txt"

mkdir -p "$ROOT/assets" "$ROOT/api"

# curl sin compresión ni caché; seguir redirects; SIN -f para no perder 404
CURLC=(-sS -L -H "Cache-Control: no-cache" -H "Pragma: no-cache" -H "Accept-Encoding: identity")

fetch_head() { # $1=url $2=headers_out
  curl "${CURLC[@]}" -D "$2" -o /dev/null "$1" || true
  # métricas
  curl "${CURLC[@]}" -w 'http_version: %{http_version}\nremote_ip: %{remote_ip}\nsize_download: %{size_download}\ntime_total: %{time_total}\n' -o /dev/null "$1" >> "$2" || true
}
fetch_body() { # $1=url $2=body_out
  curl "${CURLC[@]}" -o "$2" "$1" || true
}
hval(){ # $1=Header-Name $2=file
  grep -iE "^$1:" "$2" | head -n1 | cut -d' ' -f2- | tr -d '\r'
}
http_code(){ # $1=headers_file
  grep -m1 -E '^HTTP/' "$1" | awk '{print $2}'
}

# 1) / y /index.html
fetch_head  "$BASE"            "$ROOT/index-HEAD.txt"
fetch_head  "$BASE/index.html" "$ROOT/index-fallback-HEAD.txt"
fetch_body  "$BASE"            "$ROOT/index-remote.html"
BYTES_REMOTE_INDEX=$(wc -c < "$ROOT/index-remote.html" 2>/dev/null || echo 0)

# 2) Parse index
commit_remote="$(sed -n 's/.*name="p12-commit" content="\([0-9a-f]\{7,40\}\)".*/\1/pI' "$ROOT/index-remote.html" | head -n1)"
has_shim_remote=$([ -n "$(grep -oi 'p12-safe-shim' "$ROOT/index-remote.html" || true)" ] && echo yes || echo no)
has_single_remote=$(
  (grep -qi 'name="p12-single"' "$ROOT/index-remote.html" || grep -qi 'data-single="' "$ROOT/index-remote.html") && echo yes || echo no
)

extract_assets(){
  sed -n 's/.*<script[^>]*src=["'\'']\([^"'\'']*\)["'\''][^>]*>.*/\1/pI; s/.*<link[^>]*rel=["'\'']stylesheet["'\''][^>]*href=["'\'']\([^"'\'']*\)["'\''][^>]*>.*/\1/pI' "$1" \
  | sed -E 's/#.*$//' | grep -vE '^(https?:|data:|//)' | sed -E 's@^\./@@'
}
mapfile -t ASSETS < <(extract_assets "$ROOT/index-remote.html" | sort -u)

# 3) API endpoints
fetch_body "$BASE/api/deploy-stamp" "$ROOT/api/deploy-stamp.json"
fetch_head "$BASE/api/deploy-stamp" "$ROOT/api/deploy-stamp-HEAD.txt"
fetch_body "$BASE/health"           "$ROOT/api/health.json"
fetch_head "$BASE/health"           "$ROOT/api/health-HEAD.txt"
fetch_body "$BASE/api/notes?limit=10" "$ROOT/api/notes-10.json"
fetch_head "$BASE/api/notes?limit=10" "$ROOT/api/notes-10-HEAD.txt"
curl -sS -X OPTIONS -D "$ROOT/api/notes-OPTIONS-HEAD.txt" -o /dev/null "$BASE/api/notes" || true

# 4) Negativos
neg_like=$(curl -sS -o /dev/null -w "%{http_code}" -X POST "${BASE}/api/notes/999999999/like" || true)
neg_vget=$(curl -sS -o /dev/null -w "%{http_code}" -X GET  "${BASE}/api/notes/999999999/view" || true)
neg_vpost=$(curl -sS -o /dev/null -w "%{http_code}" -X POST "${BASE}/api/notes/999999999/view" || true)
neg_report=$(curl -sS -o /dev/null -w "%{http_code}" -X POST "${BASE}/api/notes/999999999/report" || true)
neg_summary="negativos: like=$neg_like view(GET/POST)=$neg_vget/$neg_vpost report=$neg_report"

# 5) Assets (si los hay)
printf "asset\tstatus\tcontent-type\tcache-control\tetag\tlast-modified\tbytes\tsha256\tversioning\n" > "$ROOT/assets-report.tsv"
sha_file(){ sha256sum "$1" 2>/dev/null | awk '{print $1}'; }
for a in "${ASSETS[@]}"; do
  rel="${a#/}" ; url="$BASE/$rel"
  hdr="$ROOT/assets/$(echo "$rel" | tr '/' '_').head.txt"
  out="$ROOT/assets/$(echo "$rel" | tr '/' '_').bin"
  mkdir -p "$(dirname "$out")" >/dev/null 2>&1 || true
  fetch_head "$url" "$hdr"; fetch_body "$url" "$out"
  code="$(http_code "$hdr")"
  ct="$(hval 'Content-Type' "$hdr")"
  cc="$(hval 'Cache-Control' "$hdr")"
  et="$(hval 'ETag' "$hdr")"
  lm="$(hval 'Last-Modified' "$hdr")"
  bytes="$(wc -c < "$out" 2>/dev/null || echo 0)"
  sh="$(sha_file "$out")"
  ver="no"; [[ "$a" == *\?* ]] && ver="yes"
  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$a" "${code:-MISS}" "${ct:-}" "${cc:-}" "${et:-}" "${lm:-}" "$bytes" "${sh:-MISS}" "$ver" >> "$ROOT/assets-report.tsv"
done

# 6) Heurísticas / resumen
INDEX_CT="$(hval 'Content-Type' "$ROOT/index-HEAD.txt")"
INDEX_CC="$(hval 'Cache-Control' "$ROOT/index-HEAD.txt")"
INDEX_ETAG="$(hval 'ETag' "$ROOT/index-HEAD.txt")"
INDEX_LM="$(hval 'Last-Modified' "$ROOT/index-HEAD.txt")"
DS_CODE="$(http_code "$ROOT/api/deploy-stamp-HEAD.txt")"
ALAO="$(hval 'Access-Control-Allow-Origin' "$ROOT/api/notes-OPTIONS-HEAD.txt")"
LINK_NEXT=$(grep -iE '^link:.*rel="next"' "$ROOT/api/notes-10-HEAD.txt" >/dev/null && echo yes || echo no)

warns=()
(( BYTES_REMOTE_INDEX<=10 )) && warns+=("index remoto prácticamente vacío (${BYTES_REMOTE_INDEX} bytes)")
[[ "$has_shim_remote" != "yes" ]] && warns+=("index remoto SIN p12-safe-shim")
[[ "$has_single_remote" != "yes" ]] && warns+=("index remoto SIN single-detector (meta o data-single)")
[[ -z "${INDEX_CC:-}" ]] && warns+=("index sin Cache-Control")
[[ "${DS_CODE:-}" != "200" ]] && warns+=("/api/deploy-stamp devuelve ${DS_CODE:-N/A} (se usará meta del index)")
neg_ok=false; [[ "$neg_like" == 404 && "$neg_report" == 404 && ( "$neg_vget" == 404 || "$neg_vpost" == 404 ) ]] && neg_ok=true
[[ "$neg_ok" != true ]] && warns+=("negativos no 404 → $neg_summary")

write_summary(){
  local path="$1"
  {
    echo "== paste12 REMOTE DEEP AUDIT =="
    echo "ts: $TS"
    echo "base: $BASE"
    echo
    echo "-- INDEX --"
    echo "bytes_remote_index: ${BYTES_REMOTE_INDEX}"
    echo "content-type: ${INDEX_CT:-N/A}"
    echo "cache-control: ${INDEX_CC:-N/A}"
    echo "etag: ${INDEX_ETAG:-N/A}"
    echo "last-modified: ${INDEX_LM:-N/A}"
    echo "p12-commit (meta): ${commit_remote:-N/A}"
    echo "p12-safe-shim: $has_shim_remote"
    echo "single-detector: $has_single_remote"
    echo
    echo "-- ASSETS --"
    echo "assets_total: ${#ASSETS[@]}"
    echo "assets_report: $(basename "$ROOT")/assets-report.tsv"
    echo
    echo "-- API --"
    echo "/api/deploy-stamp code: ${DS_CODE:-N/A}"
    echo "CORS preflight /api/notes A-C-A-Origin: ${ALAO:-N/A}"
    echo "Link rel=next en /api/notes?limit=10: ${LINK_NEXT}"
    echo
    echo "-- NEGATIVOS --"
    echo "$neg_summary"
    echo "negativos_ok: $neg_ok"
    echo
    echo "-- WARNINGS --"
    if ((${#warns[@]})); then for w in "${warns[@]}"; do echo "- $w"; done; else echo "(ninguna)"; fi
    echo
    echo "-- ARCHIVOS --"
    echo "$(basename "$ROOT")/index-HEAD.txt"
    echo "$(basename "$ROOT")/index-remote.html"
    echo "$(basename "$ROOT")/api/*.txt|*.json"
  } > "$path"
}

write_summary "$ROOT/summary.txt"
write_summary "$SUMMARY"

# README con recuento de códigos para que la carpeta NUNCA quede vacía
{
  echo "paste12 remote deep audit @ $TS"
  echo "Este directorio guarda headers/cuerpos incluso con 404."
  echo "Index bytes: $BYTES_REMOTE_INDEX"
  echo "Deploy-stamp code: ${DS_CODE:-N/A}"
  echo "$neg_summary"
  echo "Assets totales: ${#ASSETS[@]}"
} > "$ROOT/README.txt"

echo "OK: carpeta: $ROOT"
echo "OK: resumen directo: $SUMMARY"
