#!/usr/bin/env bash
set -u

BASE="${1:?Uso: $0 BASE_URL (ej: https://paste12-rmsk.onrender.com)}"
OUTDIR="${2:-/sdcard/Download}"
mkdir -p "$OUTDIR"

echo "=== REMOTE FE SMOKE @ $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
echo "BASE: $BASE"
echo

# helper para curl (follow, show error)
curlf() {
  curl -sS -L --fail "$@" 2>/dev/null || return 1
}

# 1) GET / (index)
echo "-- 1) GET / (index) --"
IDX_FILE="$OUTDIR/remote_index.html"
HTTP_STATUS=$(curl -sS -w "%{http_code}" -o "$IDX_FILE" -L "$BASE/" 2>/dev/null || echo "000")
echo "HTTP / -> $HTTP_STATUS"
if [[ "$HTTP_STATUS" == "200" ]]; then
  # buscar indicadores FE
  if grep -qi 'id=["'\'']notes-list["'\'']' "$IDX_FILE"; then
    echo "OK  - #notes-list: FOUND"
  else
    echo "WARN - #notes-list: NOT FOUND"
  fi

  # buscar p12 meta flags
  for meta in 'name="p12-commit"' 'p12-safe-shim' 'data-single'; do
    if grep -qi "$meta" "$IDX_FILE"; then
      echo "OK  - index flag: $meta"
    else
      echo "WARN - index flag missing: $meta"
    fi
  done

  # buscar errores en HTML (tracebacks)
  if grep -Ei "traceback|exception|error handling request|404 page not found|500 internal server error" "$IDX_FILE" | head -n1 >/dev/null; then
    echo "ERR  - posible stacktrace / error en index (primer match):"
    grep -Ei "traceback|exception|error handling request|500 internal server error|ValueError|PatternError" "$IDX_FILE" | sed -n '1,6p'
  fi
else
  echo "ERR  - GET / returned $HTTP_STATUS (ver $IDX_FILE)"
fi
echo

# 2) Encontrar JS app (app.js) y descargar
echo "-- 2) Buscar /js/app.js o script que parezca app bundle --"
SCRIPT_SRC=""
# buscar src que contenga "app.js" o "/js/"
SCRIPT_SRC=$(sed -n '1,400p' "$IDX_FILE" | tr '\n' ' ' | sed -E 's/</\n</g' | grep -iEo '<script[^>]+>' \
  | grep -iEo 'src=[\"'\''][^\"'\'']+[\"'\'']' | sed -E "s/src=['\"](.*)['\"]/\\1/" \
  | grep -Ei 'app(\.min)?\.js|/js/|main\.[a-z0-9]+\.js' | head -n1 || true)

if [[ -n "$SCRIPT_SRC" ]]; then
  # normalizar URL
  if [[ "$SCRIPT_SRC" =~ ^https?:// ]]; then
    JS_URL="$SCRIPT_SRC"
  else
    # soporta rutas relativas y absolutas
    if [[ "$SCRIPT_SRC" =~ ^/ ]]; then
      JS_URL="${BASE%/}$SCRIPT_SRC"
    else
      JS_URL="${BASE%/}/$SCRIPT_SRC"
    fi
  fi
  echo "Found script: $SCRIPT_SRC"
  echo "Resolved: $JS_URL"
  JS_FILE="$OUTDIR/remote_app_js.bundle"
  JS_STATUS=$(curl -sS -w "%{http_code}" -o "$JS_FILE" -L "$JS_URL" 2>/dev/null || echo "000")
  echo "HTTP ${JS_URL} -> $JS_STATUS"
  if [[ "$JS_STATUS" == "200" ]]; then
    echo "OK - JS loaded (size: $(stat -c%s "$JS_FILE" 2>/dev/null || echo 'n/a') bytes)"
  else
    echo "ERR - JS fetch failed (status $JS_STATUS). Check $JS_URL manually."
  fi
else
  echo "WARN - no se encontró script obvio en index que contenga 'app.js' o '/js/'."
fi
echo

# 3) GET /api/notes?limit=10
echo "-- 3) GET /api/notes?limit=10 --"
API_NOTES_URL="${BASE%/}/api/notes?limit=10"
API_OUT="$OUTDIR/api_notes.json"
API_STATUS=$(curl -sS -w "%{http_code}" -o "$API_OUT" -L "$API_NOTES_URL" 2>/dev/null || echo "000")
echo "HTTP ${API_NOTES_URL} -> $API_STATUS"
if [[ "$API_STATUS" == "200" ]]; then
  # comprobar content-type y si tiene JSON
  CT=$(grep -i '^content-type:' -m1 "$API_OUT" 2>/dev/null || true)
  # try jq if available
  if command -v jq >/dev/null 2>&1; then
    if jq empty "$API_OUT" >/dev/null 2>&1; then
      # comprobar array o object
      TYPE=$(jq -r 'type' "$API_OUT" 2>/dev/null || echo "unknown")
      echo "OK - JSON valid (jq type: $TYPE)"
      if jq 'if type=="array" then length else (keys|length) end' "$API_OUT" >/dev/null 2>&1; then
        echo "OK - JSON contiene elementos"
        jq 'if type=="array" then .[0:3] else . end' "$API_OUT" | sed -n '1,20p'
      fi
    else
      echo "ERR - /api/notes returned invalid JSON (jq parse failed). Preview:"
      sed -n '1,20p' "$API_OUT"
    fi
  else
    # fallback simple check
    if head -n1 "$API_OUT" | grep -qE '^\s*(\{|\[)'; then
      echo "OK - JSON-like output (no jq presente). Preview:"
      sed -n '1,20p' "$API_OUT"
    else
      echo "ERR - /api/notes response not JSON. Preview:"
      sed -n '1,20p' "$API_OUT"
    fi
  fi
else
  echo "ERR - /api/notes returned $API_STATUS. Preview body:"
  sed -n '1,20p' "$API_OUT"
fi
echo

# 4) POST probe to /api/notes (JSON) - only if server allows (safe attempt)
echo "-- 4) POST /api/notes (sólo prueba rápida y no destructiva) --"
TMP_POST_OUT="$OUTDIR/api_notes_post.json"
# payload pequeño; el script no fallará si POST devuelve 405/4xx
curl -sS -o "$TMP_POST_OUT" -w "HTTP%{http_code}" -L -X POST -H "Content-Type: application/json" \
  -d '{"text":"smoke test from verifier","hours":1}' "${BASE%/}/api/notes" 2>/dev/null || echo "HTTP000" \
  | sed -n '1p' > /dev/null
# get status code from file saved by curl
POST_STATUS=$(tail -n 1 "$TMP_POST_OUT" 2>/dev/null | sed -n '1p' || true)
# Because we redirected output, better to check actual HTTP code with --write-out
POST_STATUS=$(curl -sS -L -o "$TMP_POST_OUT" -w "%{http_code}" -X POST -H "Content-Type: application/json" \
  -d '{"text":"smoke test from verifier","hours":1}' "${BASE%/}/api/notes" 2>/dev/null || echo "000")
echo "HTTP POST /api/notes -> $POST_STATUS"
if [[ "$POST_STATUS" =~ ^2 ]]; then
  echo "OK - POST succeeded. Response preview:"
  sed -n '1,20p' "$TMP_POST_OUT"
elif [[ "$POST_STATUS" == "405" ]]; then
  echo "ERR - POST not allowed (405). Server Allow header:"
  curl -I -s "${BASE%/}/api/notes" | sed -n '1,20p'
else
  echo "WARN - POST returned $POST_STATUS. Response preview:"
  sed -n '1,20p' "$TMP_POST_OUT"
fi
echo

# 5) Summary
echo "=== SUMMARY ==="
echo "Index HTTP: $HTTP_STATUS"
echo "Script found: ${SCRIPT_SRC:-NONE}"
echo "Script fetch status: ${JS_STATUS:-NONE}"
echo "/api/notes GET: $API_STATUS"
echo "/api/notes POST: $POST_STATUS"
echo
echo "Artifacts saved under: $OUTDIR"
echo "Index copy: $IDX_FILE"
echo "API GET copy: $API_OUT"
echo "JS copy: ${JS_FILE:-not_downloaded}"
echo "POST response: $TMP_POST_OUT"
echo
echo "==== End ===="
