#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR] }"
OUTDIR="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
ROOT="$OUTDIR/paste12-remote-deep-$TS"
SUMMARY_ROOT="$OUTDIR/paste12-remote-deep-$TS.txt"

mkdir -p "$ROOT/assets" "$ROOT/api"

# curl: sin compresión ni caché; seguir redirects; con reintento
CURLH=(-H "Cache-Control: no-cache" -H "Pragma: no-cache" -H "Accept-Encoding: identity" -L -f --retry 2 --retry-delay 1)

fetch_headers(){ # $1=url $2=out_headers.txt
  curl -sS -D "$2" -o /dev/null "${CURLH[@]}" "$1" || true
  curl -sS -w 'http_version: %{http_version}\nremote_ip: %{remote_ip}\nsize_download: %{size_download}\ntime_total: %{time_total}\n' -o /dev/null "${CURLH[@]}" "$1" >> "$2" || true
}
http_header(){ # $1=Header-Name $2=headers_file
  grep -iE "^$1:" "$2" | head -n1 | cut -d' ' -f2- | tr -d '\r'
}

# 1) HEADERS / y /index.html
fetch_headers "$BASE"            "$ROOT/index-HEAD.txt"
fetch_headers "$BASE/index.html" "$ROOT/index-fallback-HEAD.txt"

# 2) Descargar index remoto (crudo)
curl -sS "${CURLH[@]}" "$BASE" -o "$ROOT/index-remote.html" || true
BYTES_REMOTE_INDEX=$(wc -c < "$ROOT/index-remote.html" 2>/dev/null || echo 0)

# 3) Extraer commit, flags FE y assets
commit_remote="$(sed -n 's/.*name="p12-commit" content="\([0-9a-f]\{7,40\}\)".*/\1/pI' "$ROOT/index-remote.html" | head -n1)"
has_shim_remote=$([ -n "$(grep -oi 'p12-safe-shim' "$ROOT/index-remote.html" || true)" ] && echo yes || echo no)
has_single_remote=$(
  (grep -qi 'name="p12-single"' "$ROOT/index-remote.html" || grep -qi 'data-single="' "$ROOT/index-remote.html") && echo yes || echo no
)

extract_assets(){ # rutas locales; ignora http(s), //, data:
  sed -n 's/.*<script[^>]*src=["'\'']\([^"'\'']*\)["'\''][^>]*>.*/\1/pI; s/.*<link[^>]*rel=["'\'']stylesheet["'\''][^>]*href=["'\'']\([^"'\'']*\)["'\''][^>]*>.*/\1/pI' "$1" \
  | sed -E 's/#.*$//' | grep -vE '^(https?:|data:|//)' | sed -E 's@^\./@@'
}
mapfile -t ASSETS < <(extract_assets "$ROOT/index-remote.html" | sort -u)

# 4) API endpoints
curl -sS "${CURLH[@]}" "$BASE/api/deploy-stamp" -o "$ROOT/api/deploy-stamp.json" || true
fetch_headers "$BASE/api/deploy-stamp"          "$ROOT/api/deploy-stamp-HEAD.txt" || true

curl -sS "${CURLH[@]}" "$BASE/health" -o "$ROOT/api/health.json" || true
fetch_headers "$BASE/health"                    "$ROOT/api/health-HEAD.txt" || true

curl -sS "${CURLH[@]}" "$BASE/api/notes?limit=10" -o "$ROOT/api/notes-10.json" || true
fetch_headers "$BASE/api/notes?limit=10"        "$ROOT/api/notes-10-HEAD.txt" || true
curl -sS -X OPTIONS -D "$ROOT/api/notes-OPTIONS-HEAD.txt" -o /dev/null "${CURLH[@]}" "$BASE/api/notes" || true

# 5) Negativos 404 (solo remoto)
neg_like=$(curl -sS -o /dev/null -w "%{http_code}" -X POST "${BASE}/api/notes/999999999/like" || true)
neg_vget=$(curl -sS -o /dev/null -w "%{http_code}" -X GET  "${BASE}/api/notes/999999999/view" || true)
neg_vpost=$(curl -sS -o /dev/null -w "%{http_code}" -X POST "${BASE}/api/notes/999999999/view" || true)
neg_report=$(curl -sS -o /dev/null -w "%{http_code}" -X POST "${BASE}/api/notes/999999999/report" || true)

# 6) Assets: bajar y auditar
printf "asset\tstatus\tcontent-type\tcache-control\tetag\tlast-modified\tbytes\tsha256\tversioning\n" > "$ROOT/assets-report.tsv"

sha_file(){ sha256sum "$1" 2>/dev/null | awk '{print $1}'; }

for a in "${ASSETS[@]}"; do
  rel="${a#/}" ; url="$BASE/$rel"
  hdr="$ROOT/assets/$(echo "$rel" | tr '/' '_').head.txt"
  out="$ROOT/assets/$(echo "$rel" | tr '/' '_').bin"
  mkdir -p "$(dirname "$out")" >/dev/null 2>&1 || true

  curl -sS -D "$hdr" -o "$out" "${CURLH[@]}" "$url" || true
  code=$(grep -m1 -E '^HTTP/' "$hdr" | awk '{print $2}')
  ct=$(http_header "Content-Type" "$hdr")
  cc=$(http_header "Cache-Control" "$hdr")
  et=$(http_header "ETag" "$hdr")
  lm=$(http_header "Last-Modified" "$hdr")
  bytes=$(wc -c < "$out" 2>/dev/null || echo 0)
  sh=$(sha_file "$out")
  ver="no"; [[ "$a" == *\?* ]] && ver="yes"
  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$a" "${code:-MISS}" "${ct:-}" "${cc:-}" "${et:-}" "${lm:-}" "$bytes" "${sh:-MISS}" "$ver" >> "$ROOT/assets-report.tsv"
done

# 7) Heurísticas / resumen
INDEX_CT=$(http_header "Content-Type" "$ROOT/index-HEAD.txt")
INDEX_CC=$(http_header "Cache-Control" "$ROOT/index-HEAD.txt")
INDEX_ETAG=$(http_header "ETag" "$ROOT/index-HEAD.txt")
INDEX_LM=$(http_header "Last-Modified" "$ROOT/index-HEAD.txt")
DS_CODE=$(grep -m1 -E '^HTTP/' "$ROOT/api/deploy-stamp-HEAD.txt" | awk '{print $2}')
ALAO=$(http_header "Access-Control-Allow-Origin" "$ROOT/api/notes-OPTIONS-HEAD.txt")
LINK_NEXT=$(grep -iE '^link:.*rel="next"' "$ROOT/api/notes-10-HEAD.txt" >/dev/null && echo yes || echo no)

warns=()
(( BYTES_REMOTE_INDEX<=10 )) && warns+=("index remoto prácticamente vacío (${BYTES_REMOTE_INDEX} bytes)")
[[ "$has_shim_remote" != "yes" ]] && warns+=("index remoto SIN p12-safe-shim")
[[ "$has_single_remote" != "yes" ]] && warns+=("index remoto SIN single-detector (meta o data-single)")
[[ -z "$INDEX_CC" ]] && warns+=("index sin Cache-Control")
[[ "${DS_CODE:-}" != "200" ]] && warns+=("/api/deploy-stamp devuelve ${DS_CODE:-N/A} (se usará meta del index)")
neg_summary="negativos: like=$neg_like view(GET/POST)=$neg_vget/$neg_vpost report=$neg_report"
neg_ok=false; [[ "$neg_like" == 404 && "$neg_report" == 404 && ( "$neg_vget" == 404 || "$neg_vpost" == 404 ) ]] && neg_ok=true
[[ "$neg_ok" != true ]] && warns+=("negativos no 404 → $neg_summary")

# 8) Escribir resumen (en la carpeta y como archivo suelto en OUTDIR)
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
write_summary "$SUMMARY_ROOT"

echo "OK: carpeta: $ROOT"
echo "OK: resumen directo: $SUMMARY_ROOT"
