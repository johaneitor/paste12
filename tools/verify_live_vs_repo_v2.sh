#!/usr/bin/env bash
# Uso: tools/verify_live_vs_repo_v2.sh <BASE> [/sdcard/Download]
set -euo pipefail
BASE="${1:-}"
OUTDIR="${2:-/sdcard/Download}"
[[ -n "$BASE" ]] || { echo "ERROR: falta BASE"; exit 2; }
mkdir -p "$OUTDIR"

TS="$(date -u +%Y%m%d-%H%M%SZ)"
LIVE_HTML="$OUTDIR/index-live-$TS.html"
LOC_HTML="$OUTDIR/index-local-$TS.html"
REPORT="$OUTDIR/frontend-compare-$TS.txt"

# 1) traer live con cache-bust y sin SW
Q="nosw=1&v=$(date +%s)"
curl -fsSL "$BASE/?$Q" -o "$LIVE_HTML" || { echo "ERROR: no pude bajar $BASE"; exit 3; }

# 2) copiar local
[[ -f frontend/index.html ]] && cp -f frontend/index.html "$LOC_HTML" || echo "WARN: no existe frontend/index.html"

# 3) checks
sha_live=$(sha256sum "$LIVE_HTML" | awk '{print $1}')
sha_loc=$(sha256sum "$LOC_HTML" 2>/dev/null | awk '{print $1}')
{
  echo "== verify_live_vs_repo_v2 =="
  echo "BASE: $BASE"
  echo "ts  : $TS"
  echo "live: $LIVE_HTML"
  echo "loc : $LOC_HTML"
  echo "sha live: $sha_live"
  echo "sha loc : ${sha_loc:-N/A}"
  [[ "$sha_live" != "${sha_loc:-}" ]] && echo "WARN- HTML remoto distinto al repo" || echo "OK- live coincide con repo"

  echo
  echo "-- checks en remoto --"
  grep -qi 'hotfix v5' "$LIVE_HTML" && echo "OK  - hotfix v5 presente" || echo "WARN- hotfix v5 ausente"
  grep -qi 'class="views"' "$LIVE_HTML" && echo "OK  - views span (.views)" || echo "FAIL- views span (.views)"
  grep -qi 'google-adsense-account' "$LIVE_HTML" && echo "OK  - AdSense meta" || echo "FAIL- AdSense meta"
  grep -qi 'pagead2\.googlesyndication' "$LIVE_HTML" && echo "OK  - AdSense script" || echo "FAIL- AdSense script"

  echo
  echo "-- checks en local --"
  [[ -f "$LOC_HTML" ]] || { echo "WARN- sin local"; exit 0; }
  grep -qi 'class="views"' "$LOC_HTML" && echo "OK  - views span (.views)" || echo "FAIL- views span (.views)"
  grep -qi 'google-adsense-account' "$LOC_HTML" && echo "OK  - AdSense meta" || echo "FAIL- AdSense meta"
  grep -qi 'pagead2\.googlesyndication' "$LOC_HTML" && echo "OK  - AdSense script" || echo "FAIL- AdSense script"
} | tee "$REPORT"

echo "OK: reporte $REPORT"
