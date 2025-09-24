#!/usr/bin/env bash
set -euo pipefail

BASE="${1:-https://paste12-rmsk.onrender.com}"

pick(){ for d in "/sdcard/Download" "/storage/emulated/0/Download" "$HOME/Download" "$HOME/downloads"; do [ -d "$d" ] && [ -w "$d" ] && { echo "$d"; return; }; done; echo "$HOME"; }
DEST="$(pick)"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
OUT="$DEST/fe-be-audit-$TS.txt"

TMPD="$(mktemp -d)"; trap 'rm -rf "$TMPD"' EXIT
: > "$OUT"

line(){ printf '%s\n' "$*" >> "$OUT"; }
title(){ printf '\n== %s ==\n' "$*" >> "$OUT"; }
kv(){ printf '%-28s %s\n' "• $1:" "$2" >> "$OUT"; }

line "# Frontend↔Backend Interaction Audit — $TS"
kv "Base" "$BASE"
kv "Destino" "$OUT"

# 1) CORS mínimo
title "OPTIONS /api/notes (CORS)"
curl -sS -i -X OPTIONS "$BASE/api/notes" | sed -n '1,40p' >> "$OUT" || line "<error>"

# 2) Publish JSON + FORM
title "Publish JSON"
RJSON="$TMPD/rjson.txt"
curl -sS -i -H 'Content-Type: application/json' \
  --data '{"text":"fe-be audit json —— 1234567890 abcdefghij"}' "$BASE/api/notes" \
  | tee "$RJSON" | sed -n '1,40p' >> "$OUT" || :
ID_JSON="$(sed -n 's/.*"id":[ ]*\([0-9][0-9]*\).*/\1/p' "$RJSON" | tail -n1 || true)"

title "Publish FORM"
RFORM="$TMPD/rform.txt"
curl -sS -i -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode "text=fe-be audit form —— 1234567890 abcdefghij" "$BASE/api/notes" \
  | tee "$RFORM" | sed -n '1,40p' >> "$OUT" || :
ID_FORM="$(sed -n 's/.*"id":[ ]*\([0-9][0-9]*\).*/\1/p' "$RFORM" | tail -n1 || true)"

CID="${ID_FORM:-$ID_JSON}"
title "like/view para id=$CID"
if [ -n "${CID:-}" ]; then
  curl -sS -X POST "$BASE/api/notes/$CID/like" >> "$OUT" || line "<like error>"
  line ""
  curl -sS -X POST "$BASE/api/notes/$CID/view" >> "$OUT" || line "<view error>"
else
  line "<no hay ID para like/view>"
fi

# 3) Verificación FE single
title "GET /?id=$CID&nosw=1  → flags single"
H1="$TMPD/single.html"
curl -fsS "$BASE/?id=$CID&nosw=1&_=$TS" -o "$H1" || :
HAS_META=$([ -s "$H1" ] && grep -Fqi '<meta name="p12-single"' "$H1" && echo yes || echo no)
HAS_BODY=$([ -s "$H1" ] && grep -Fqi 'data-single="1"' "$H1" && echo yes || echo no)
kv "single meta" "$HAS_META"
kv "single body" "$HAS_BODY"

title "GET /?nosw=1 (base)  → NO debe tener p12-single"
H0="$TMPD/index.html"
curl -fsS "$BASE/?nosw=1&_=$TS" -o "$H0" || :
BASE_HAS_META=$([ -s "$H0" ] && grep -Fqi '<meta name="p12-single"' "$H0" && echo yes || echo no)
kv "index con p12-single" "$BASE_HAS_META"

# 4) Encadenado: paginación y headers que afectan FE
title "GET /api/notes?limit=3 (headers)"
curl -sS -i "$BASE/api/notes?limit=3" | sed -n '1,30p' >> "$OUT" || line "<error>"

title "Resumen final"
kv "ID JSON" "${ID_JSON:-<n/a>}"
kv "ID FORM" "${ID_FORM:-<n/a>}"
kv "Single meta" "$HAS_META"
kv "Single body" "$HAS_BODY"
kv "Index trae p12-single" "$BASE_HAS_META"
kv "Archivo" "$OUT"

echo "OK: $OUT"
