#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://tu-dominio}"
OUTDIR="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
mkdir -p "$OUTDIR"

rep="$OUTDIR/fe-be-audit-$TS.txt"
: > "$rep"

say(){ echo "$@" | tee -a "$rep"; }

say "== FE/BE Deep Audit =="
say "base : $BASE"
say "ts   : $TS"
say ""

# ---- Backend basics
HJSON="$OUTDIR/health-$TS.json"
curl -fsS "$BASE/api/health" -H 'Accept: application/json' -o "$HJSON"
say "health: $(cat "$HJSON")"

hdrs="$OUTDIR/api-notes-headers-$TS.txt"
curl -fsSI "$BASE/api/notes?limit=10" > "$hdrs"
say "-- /api/notes headers --"
tail -n +1 "$hdrs" | sed 's/\r$//' | grep -E 'HTTP/2|Content-Type|Access-Control|Link|X-Next-Cursor' | tee -a "$rep"
say ""

# ---- Frontend HTML
INDEX="$OUTDIR/index-$TS.html"
curl -fsSL "$BASE/?debug=1&nosw=1&v=$TS" -o "$INDEX"
say "index saved: $INDEX"

chk(){
  local label="$1" rx="$2"
  if grep -qE "$rx" "$INDEX"; then say "OK  - $label"; else say "FAIL- $label"; fi
}
chk "hotfix v4"          'id="p12-hotfix-v4"'
chk "views span"         'class="views"'
chk "summary-enhancer"   'id="summary-enhancer"'
chk "AdSense tag"        'pagead2\.googlesyndication\.com/pagead/js/adsbygoogle\.js'
chk "Link/next hint"     'rel="next"|X-Next-Cursor'

# ---- CORS/OPTIONS
hdrs_cors="$OUTDIR/options-$TS.txt"
curl -fsSI -X OPTIONS "$BASE/api/notes" > "$hdrs_cors"
say ""
say "-- OPTIONS /api/notes --"
grep -Ei 'HTTP/2|allow|access-control|max-age' "$hdrs_cors" | tee -a "$rep"

# ---- Publish JSON & FORM
post_json="$OUTDIR/post-json-$TS.json"
curl -fsS -H 'Content-Type: application/json' -H 'Accept: application/json' \
     -d '{"text":"test suite ascii 123456"}' \
     "$BASE/api/notes" -o "$post_json"
say ""
say "POST json -> $(wc -c < "$post_json") bytes"

post_form="$OUTDIR/post-form-$TS.json"
curl -fsS -H 'Content-Type: application/x-www-form-urlencoded' -H 'Accept: application/json' \
     -d 'text=form%20shim%20create' \
     "$BASE/api/notes" -o "$post_form"
say "POST form -> $(wc -c < "$post_form") bytes"

say ""
say "Archivos:"
say "  $HJSON"
say "  $hdrs"
say "  $INDEX"
say "  $hdrs_cors"
say "  $post_json"
say "  $post_form"
say ""
say "Hecho."
