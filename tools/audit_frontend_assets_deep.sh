#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }
TMPDIR_USE="${TMPDIR:-$HOME/tmp}"
mkdir -p "$TMPDIR_USE"
TMP="$TMPDIR_USE/feaudit.$$.tmp"
mkdir -p "${TMP%/*}"

say(){ echo -e "$*"; }
sep(){ echo "---------------------------------------------"; }

abs() {
  local href="$1"
  if [[ "$href" =~ ^https?:// ]]; then echo "$href"; return 0; fi
  if [[ "$href" =~ ^/ ]]; then echo "${BASE%/}$href"; return 0; fi
  echo "${BASE%/}/$href"
}

say "== FETCH index.html =="
curl -fsSL --compressed "$BASE/" -o "$TMP.index.html"
BYTES=$(wc -c < "$TMP.index.html" | tr -d ' ')
echo "bytes: $BYTES"; sep

say "== Scripts y preloads detectados =="
grep -Eio '<script[^>]+src="[^"]+"' "$TMP.index.html" | sed -E 's/.*src="([^"]+)".*/\1/' | sed 's/^/script: /' || true
grep -Eio '<script[^>]*>([^<]|<[^/]|</[^s]|</s[^c]|</sc[^r]|</scr[^i]|</scrip[^t])*</script>' "$TMP.index.html" >/dev/null 2>&1 && echo "inline_script: yes" || echo "inline_script: no"
grep -Eio '<link[^>]+rel="modulepreload"[^>]+href="[^"]+"' "$TMP.index.html" | sed -E 's/.*href="([^"]+)".*/\1/' | sed 's/^/modulepreload: /' || true
grep -Eio '<link[^>]+rel="manifest"[^>]+href="[^"]+"' "$TMP.index.html" | sed -E 's/.*href="([^"]+)".*/\1/' | sed 's/^/manifest: /' || true
sep

say "== Descarga y escaneo de JS (hasta 10) =="
JS_LIST=$(grep -Eio '<script[^>]+src="[^"]+"' "$TMP.index.html" | sed -E 's/.*src="([^"]+)".*/\1/' | head -n 10 || true)
CNT=0
for s in $JS_LIST; do
  CNT=$((CNT+1))
  URL="$(abs "$s")"
  OUT="$TMP.js.$CNT.js"
  echo "• $URL"
  if ! curl -fsSL --compressed "$URL" -o "$OUT"; then
    echo "  (falló descarga)"; continue
  fi
  USED=$(grep -Eo 'fetch\([^)]*\)' "$OUT" | sed 's/^/  fetch: /' | head -n 15 || true)
  SW=$(grep -Eo 'serviceWorker\.register|navigator\.serviceWorker' "$OUT" | head -n 1 || true)
  OFF=$(grep -Eo 'offset=' "$OUT" | head -n 1 || true)
  CUR=$(grep -Eo 'cursor_ts|cursor_id|X-Next-Cursor' "$OUT" | sort -u | paste -sd, - || true)
  LIKE=$(grep -Eo '/api/notes/[${}[:alnum:]_\\]+/like' "$OUT" | head -n 1 || true)
  echo "$USED"
  [ -n "$SW" ] && echo "  sw: $SW" || true
  [ -n "$OFF" ] && echo "  uses_offset: yes" || true
  [ -n "$CUR" ] && echo "  keyset_markers: $CUR" || true
  [ -n "$LIKE" ] && echo "  like_path_sample: $LIKE" || true
done
[ "$CNT" -eq 0 ] && echo "(no se detectaron scripts externos)"
sep

echo "TMP: $TMPDIR_USE"
