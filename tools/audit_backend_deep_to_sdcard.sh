#!/usr/bin/env bash
set -euo pipefail

BASE="${1:-https://paste12-rmsk.onrender.com}"

pick(){ for d in "/sdcard/Download" "/storage/emulated/0/Download" "$HOME/Download" "$HOME/downloads"; do [ -d "$d" ] && [ -w "$d" ] && { echo "$d"; return; }; done; echo "$HOME"; }
DEST="$(pick)"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
OUT="$DEST/backend-audit-$TS.txt"

line(){ printf '%s\n' "$*" >> "$OUT"; }
title(){ printf '\n== %s ==\n' "$*" >> "$OUT"; }
kv(){ printf '%-28s %s\n' "• $1:" "$2" >> "$OUT"; }

TMPD="$(mktemp -d)"; trap 'rm -rf "$TMPD"' EXIT

: > "$OUT"
line "# Backend Deep Audit — $TS"
kv "Base" "$BASE"
kv "Destino" "$OUT"

# Health
title "health"
curl -sS "$BASE/api/health" >> "$OUT" || line "<error>"

# Preflight CORS
title "OPTIONS /api/notes"
curl -sS -i -X OPTIONS "$BASE/api/notes" | sed -n '1,60p' >> "$OUT" || line "<error>"

# Paginación
title "GET /api/notes?limit=5 (headers)"
curl -sS -i "$BASE/api/notes?limit=5" | sed -n '1,40p' >> "$OUT" || line "<error>"

title "GET /api/notes?limit=5 (body)"
BODY="$TMPD/notes.json"
curl -fsS "$BASE/api/notes?limit=5" -o "$BODY" || : 
cat "$BODY" >> "$OUT" || :

ICOUNT="$(grep -Fo '"id":' "$BODY" | wc -l | tr -d ' ')"
title "Resumen lista"
kv "items contados" "${ICOUNT:-0}"

# Publish JSON
title "POST /api/notes (JSON)"
RJSON="$TMPD/rjson.txt"
curl -sS -i -H 'Content-Type: application/json' \
  --data '{"text":"backend-audit json —— 1234567890 abcdefghij"}' \
  "$BASE/api/notes" | tee "$RJSON" | sed -n '1,40p' >> "$OUT" || :
ID_JSON="$(sed -n 's/.*"id":[ ]*\([0-9][0-9]*\).*/\1/p' "$RJSON" | tail -n1 || true)"

# Publish FORM
title "POST /api/notes (FORM)"
RFORM="$TMPD/rform.txt"
curl -sS -i -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode "text=backend-audit form —— 1234567890 abcdefghij" \
  "$BASE/api/notes" | tee "$RFORM" | sed -n '1,40p' >> "$OUT" || :
ID_FORM="$(sed -n 's/.*"id":[ ]*\([0-9][0-9]*\).*/\1/p' "$RFORM" | tail -n1 || true)"

CID="${ID_FORM:-$ID_JSON}"

title "like/view para id=$CID"
if [ -n "${CID:-}" ]; then
  curl -sS -X POST "$BASE/api/notes/$CID/like" >> "$OUT" || line "<like error>"
  line ""
  curl -sS -X POST "$BASE/api/notes/$CID/view" >> "$OUT" || line "<view error>"
else
  line "<no se obtuvo ID para like/view>"
fi

# HEAD opcional
title "HEAD / (no bloqueante)"
curl -sS -I "$BASE/" | sed -n '1,25p' >> "$OUT" || line "<HEAD error>"

title "HEAD /index.html (no bloqueante)"
curl -sS -I "$BASE/index.html" | sed -n '1,25p' >> "$OUT" || line "<HEAD error>"

title "Resumen final"
kv "ID JSON" "${ID_JSON:-<n/a>}"
kv "ID FORM" "${ID_FORM:-<n/a>}"
kv "Archivo" "$OUT"

echo "OK: $OUT"
