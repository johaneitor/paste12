#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://tu-dominio}"
CID="${2:-ca-pub-9479870293204581}"
OUTDIR="${3:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
R="${OUTDIR}/legal-audit-${TS}.txt"

probe() {
  local path="$1" tag="$2"
  local f="${OUTDIR}/index_${tag}-${TS}.html"
  local code
  code="$(curl -sS -o "$f" -w "%{http_code}" "$BASE/$path")" || code="000"
  local head tagc cidc
  head="$(grep -c -i '<head' "$f" || true)"
  tagc="$(grep -c 'pagead2\.googlesyndication\.com/pagead/js/adsbygoogle\.js' "$f" || true)"
  cidc="$(grep -c "client=${CID}" "$f" || true)"
  printf -- "-- /%s -- code:%s HEAD:%s TAG:%s CID:%s\nfile:%s\n\n" "$path" "$code" "$head" "$tagc" "$cidc" "file:$f" >> "$R"
  echo "$code"
}

mkdir -p "$OUTDIR"
echo "base: $BASE" > "$R"
echo "ts  : $TS"   >> "$R"
echo              >> "$R"

c1="$(probe ''         '_')"
c2="$(probe 'terms'    'terms')"
c3="$(probe 'privacy'  'privacy')"

RES="OK"
for c in "$c1" "$c2" "$c3"; do
  [[ "$c" == "200" ]] || RES="FAIL"
done

echo "RESULT: $RES" >> "$R"
echo "Guardado: $R"
