#!/usr/bin/env bash
set -euo pipefail

# Uso: tools/audit_download_texts_v1.sh BASE_URL [OUTDIR] [MAX]
# Descarga hasta MAX (clamp 10) textos de /api/notes a OUTDIR (por defecto /sdcard/Download).

BASE="${1:?Uso: $0 BASE_URL [OUTDIR] [MAX]}"
OUTDIR="${2:-/sdcard/Download}"
MAX="${3:-10}"

# Clamp MAX a [1,10]
if ! [[ "$MAX" =~ ^[0-9]+$ ]]; then MAX=10; fi
if [ "$MAX" -gt 10 ]; then MAX=10; fi
if [ "$MAX" -lt 1 ]; then MAX=1; fi

# Prepara destino
if ! mkdir -p "$OUTDIR" 2>/dev/null; then
  echo "No puedo crear '$OUTDIR' (permiso denegado). Pasa un OUTDIR alternativo como 2º argumento." >&2
  exit 1
fi

TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT

# Lista notas (máximo MAX)
HTTP_CODE="$(curl -sS -H 'Accept: application/json' -w '%{http_code}' -o "$TMP" "$BASE/api/notes?limit=$MAX" || true)"
if [ "${HTTP_CODE}" -lt 200 ] || [ "${HTTP_CODE}" -ge 300 ]; then
  echo "HTTP ${HTTP_CODE} al listar notas" >&2
  cat "$TMP" >&2 || true
  exit 2
fi

# Escribe archivos uno por nota
if command -v jq >/dev/null 2>&1; then
  jq -c '.items // [] | .[0:'"$MAX"'] | .[] | {id,text}' "$TMP" | while IFS= read -r line; do
    id="$(printf '%s' "$line" | jq -r '.id')"
    text="$(printf '%s' "$line" | jq -r '.text // ""')"
    [ -z "${id}" ] && continue
    file="$OUTDIR/paste12-note-${id}.txt"
    printf '%s' "$text" > "$file"
    echo "Descargado: $file"
  done
else
  python3 - "$OUTDIR" "$MAX" "$TMP" << 'PY'
import sys, json, os
outdir = sys.argv[1]
limit = int(sys.argv[2])
with open(sys.argv[3], 'r', encoding='utf-8') as fh:
    data = json.load(fh)
items = []
if isinstance(data, dict):
    items = data.get('items') or []
elif isinstance(data, list):
    items = data
for it in items[:limit]:
    nid = it.get('id')
    text = it.get('text') or ''
    if nid is None:
        continue
    path = os.path.join(outdir, f"paste12-note-{int(nid)}.txt")
    with open(path, 'w', encoding='utf-8') as f:
        f.write(text)
    print(f"Descargado: {path}")
PY
fi

echo "Completado. Archivos en: $OUTDIR"
