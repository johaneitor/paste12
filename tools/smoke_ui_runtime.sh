#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-${BASE:-https://paste12-rmsk.onrender.com}}"
echo "== smoke_ui_runtime @ $BASE =="

HTML="$(mktemp)"; trap 'rm -f "$HTML"' EXIT
curl -sS "$BASE/" > "$HTML"

echo "-- checks --"
grep -q 'actions\.css' "$HTML" && echo "ok: actions.css link" || echo "WARN: sin <link actions.css>"
grep -q 'actions\.js'  "$HTML" && echo "ok: actions.js script" || echo "WARN: sin <script actions.js>"

CNT_DATA=$(grep -o 'data-note-id="\?[0-9]\+"' "$HTML" | wc -l | tr -d ' ')
CNT_NOTE=$(grep -o 'id="note-[0-9]\+"' "$HTML" | wc -l | tr -d ' ')
echo "data-note-id en HTML: $CNT_DATA"
echo "id=note-* en HTML:    $CNT_NOTE"

if [[ "$CNT_DATA" -eq 0 && "$CNT_NOTE" -eq 0 ]]; then
  echo "HINT: si la UI genera las tarjetas por JS en runtime, el atributo data-note-id lo pone /js/app.js."
  echo "      asegurate que (al crear cada tarjeta) hagas: el.dataset.noteId = String(note.id); el.id = 'note-'+note.id;"
fi

echo "✅ listo"
