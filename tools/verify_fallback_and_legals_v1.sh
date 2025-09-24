#!/usr/bin/env bash
set -euo pipefail

BASE="${1:-}"
OUTDIR="${2:-/sdcard/Download}"
[[ -n "$BASE" ]] || { echo "Uso: $0 https://tu-base [/sdcard/Download]"; exit 2; }
mkdir -p "$OUTDIR"

TS="$(date -u +%Y%m%d-%H%M%SZ)"
R="$OUTDIR/fallback-legal-audit-$TS.txt"

cecho(){ echo "[$TS] $*"; echo "[$TS] $*" >> "$R"; }

cecho "== fallback + legales =="

check(){
  local path="$1"
  local url="$BASE$path"
  local f="$OUTDIR/index_${path//\//-}-$TS.html"
  code="$(curl -s -o "$f" -w "%{http_code}" "$url?debug=1&nosw=1&v=$TS")"
  head_ok="$(grep -ic '<head' "$f" || true)"
  titles="$(grep -ic '<title' "$f" || true)"
  h1s="$(grep -ic '<h1' "$f" || true)"
  cecho "-- $path -- code:$code head:$head_ok title_count:$titles h1_count:$h1s"
}

check "/"
check "/terms"
check "/privacy"

cecho "Guardado: $R"
echo "$R"
