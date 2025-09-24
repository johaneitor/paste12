#!/usr/bin/env bash
set -euo pipefail

BASE="${1:-}"
OUTDIR="${2:-/sdcard/Download}"
[[ -n "$BASE" ]] || { echo "Uso: $0 https://tu-base [/sdcard/Download]"; exit 2; }
mkdir -p "$OUTDIR"

TS="$(date -u +%Y%m%d-%H%M%SZ)"
R="$OUTDIR/unified-frontend-audit-$TS.txt"

cecho(){ echo "[$TS] $*"; echo "[$TS] $*" >> "$R"; }

cecho "== Unified Frontend Audit =="

# 1) Health
H="$OUTDIR/health-$TS.json"
curl -sS "$BASE/api/health" -o "$H" || true
cecho "-- health --"
cecho "$(cat "$H" 2>/dev/null || echo 'N/A')"

# 2) OPTIONS /api/notes
O="$OUTDIR/options-$TS.txt"
curl -sSI -X OPTIONS "$BASE/api/notes" > "$O" || true
cecho "-- OPTIONS /api/notes --"
cecho "$(head -n 20 "$O" 2>/dev/null || echo 'N/A')"

# 3) GET /api/notes (headers) (tolerar 500, queremos ver qué llega)
NH="$OUTDIR/api-notes-h-$TS.txt"
curl -sSI "$BASE/api/notes?limit=10" > "$NH" || true
cecho "-- GET /api/notes (headers) --"
cecho "$(head -n 20 "$NH" 2>/dev/null || echo 'N/A')"

# 4) GET index con cache-bust + sw off
I="$OUTDIR/index-nocache-$TS.html"
curl -sS "$BASE/?debug=1&nosw=1&v=$TS" -o "$I" || true

# 5) Chequeos: AdSense + metadatos + duplicados
HEADS="$(grep -ic '<head' "$I" || true)"
ADS_HEAD="$(grep -ic 'pagead2.googlesyndication.com/pagead/js/adsbygoogle.js' "$I" || true)"
ADS_CID="$(grep -o 'client=ca-pub-[A-Za-z0-9]+' "$I" | head -n1 || true)"
META_COMMIT="$(grep -o '<meta name="p12-commit"[^>]*>' "$I" | head -n1 || true)"
TITLE_COUNT="$(grep -ic '<title' "$I" || true)"
H1_COUNT="$(grep -ic '<h1' "$I" || true)"

cecho "-- index checks --"
cecho "head:$HEADS ads_tag:$ADS_HEAD ads_cid:${ADS_CID:-none} meta_commit:${META_COMMIT:-none} title_count:$TITLE_COUNT h1_count:$H1_COUNT"

# 6) Guardar rutas legales (para revisión manual)
curl -sS "$BASE/terms?nosw=1&v=$TS"    -o "$OUTDIR/index_terms-$TS.html" || true
curl -sS "$BASE/privacy?nosw=1&v=$TS"  -o "$OUTDIR/index_privacy-$TS.html" || true

cecho "Archivos:"
cecho "  $H"
cecho "  $O"
cecho "  $NH"
cecho "  $I"
cecho "  $OUTDIR/index_terms-$TS.html"
cecho "  $OUTDIR/index_privacy-$TS.html"
cecho "== FIN =="

echo "$R"
