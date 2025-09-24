#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-${BASE:-https://paste12-rmsk.onrender.com}}"
echo "== smoke_front @ $BASE =="

have() { curl -sS -I "$1" | head -n1 | grep -q "200"; }

echo "-- index.html referencia actions.* --"
html=$(curl -sS "$BASE/")
echo "$html" | grep -q '/css/actions.css' && echo "ok: actions.css link" || { echo "FAIL no /css/actions.css"; exit 2; }
echo "$html" | grep -q '/js/actions.js'    && echo "ok: actions.js  script" || { echo "FAIL no /js/actions.js";  exit 2; }

echo "-- HEAD assets --"
have "$BASE/css/actions.css" && echo "ok: /css/actions.css" || { echo "FAIL css"; exit 2; }
have "$BASE/js/actions.js"    && echo "ok: /js/actions.js"   || { echo "FAIL js";  exit 2; }

echo "-- contenido de /js/actions.js (selectores clave) --"
js=$(curl -sS "$BASE/js/actions.js")
echo "$js" | grep -q "note-menu"        && echo "ok: contiene 'note-menu'"        || { echo "FAIL note-menu";        exit 2; }
echo "$js" | grep -q "deriveId"         && echo "ok: contiene 'deriveId'"         || { echo "FAIL deriveId";         exit 2; }
echo "$js" | grep -q "DOMContentLoaded" && echo "ok: contiene 'DOMContentLoaded'" || { echo "FAIL DOMContentLoaded"; exit 2; }

echo "✅ smoke_front OK"
