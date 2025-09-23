#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://dominio}"
OUTDIR="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"; mkdir -p "$OUTDIR"
rep="$OUTDIR/fe-be-audit-$TS.txt"; : > "$rep"
say(){ echo "$@" | tee -a "$rep"; }

say "== FE/BE Deep Audit v9 =="; say "base: $BASE"; say "ts: $TS"; say ""

# Health
HJSON="$OUTDIR/health-$TS.json"
curl -sS "$BASE/api/health" -H 'Accept: application/json' -o "$HJSON" || true
say "health: $(cat "$HJSON" 2>/dev/null || echo 'N/A')"

# Notes headers
HDR="$OUTDIR/api-notes-headers-$TS.txt"
curl -sS -D "$HDR" -o /dev/null "$BASE/api/notes?limit=10" || true
say "-- /api/notes headers --"
grep -Ei 'HTTP/|Content-Type|Access-Control|Link|X-Next-Cursor' "$HDR" | sed 's/\r$//' | tee -a "$rep"; say ""

# Notes body + code
BODY="$OUTDIR/api-notes-$TS.json"
CODE=$(curl -sS -w '%{http_code}' -o "$BODY" "$BASE/api/notes?limit=10")
say "-- /api/notes body -- code:$CODE"; wc -c "$BODY" | tee -a "$rep"
if [[ "$CODE" != "200" ]]; then
  say "WARN: /api/notes devolvió $CODE. Guardado cuerpo para inspección: $BODY"
fi

# OPTIONS CORS
OPT="$OUTDIR/options-$TS.txt"
curl -sS -X OPTIONS -D "$OPT" -o /dev/null "$BASE/api/notes" || true
say ""; say "-- OPTIONS /api/notes --"
grep -Ei 'HTTP/|allow|access-control|max-age' "$OPT" | sed 's/\r$//' | tee -a "$rep"

# Frontend
IDX="$OUTDIR/index-$TS.html"
curl -sS -L "$BASE/?debug=1&nosw=1&v=$TS" -o "$IDX" || true
say ""; say "-- index checks --"
grep -q 'id="p12-hotfix-v4"' "$IDX" && say "OK  - hotfix v4" || say "FAIL- hotfix v4"
grep -q 'class="views"'     "$IDX" && say "OK  - views span" || say "WARN- views span"
grep -q 'pagead2\.googlesyndication\.com/pagead/js/adsbygoogle\.js' "$IDX" && say "OK  - AdSense tag" || say "WARN- AdSense tag"

say ""; say "Archivos:"
for f in "$HJSON" "$HDR" "$BODY" "$OPT" "$IDX"; do say "  $f"; done
say "Hecho."
