#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"
MAX="${2:-2160}"

tmpdir="$(mktemp -d)"
hdr="$tmpdir/h"
body="$tmpdir/b"

# Creamos nota pidiendo 99999h; capturamos headers y body
curl -sS -D "$hdr" -o "$body" \
  -X POST "$BASE/api/notes" \
  -H 'Content-Type: application/json' \
  -d '{"text":"ttl stdlib test","hours":99999}'

# Extraemos datos
id="$(jq -r '.item.id' "$body")"
ts="$(jq -r '.item.timestamp' "$body")"
ex="$(jq -r '.item.expires_at' "$body")"
hdr_max="$(grep -i '^X-Max-TTL-Hours:' "$hdr" | tail -1 | awk '{print $2}' | tr -d '\r')"

# Cálculo de delta en horas con Python estándar (fromisoformat soporta ' ' y '+00:00')
delta="$(python - "$ts" "$ex" <<'PY'
import sys, datetime as dt
ts = dt.datetime.fromisoformat(sys.argv[1].replace('Z','+00:00'))
ex = dt.datetime.fromisoformat(sys.argv[2].replace('Z','+00:00'))
print(((ex-ts).total_seconds())/3600.0)
PY
)"

printf "note: %s\n" "$id"
printf "X-Max-TTL-Hours (header): %s\n" "${hdr_max:-<sin-header>}"
printf "TTL calculado: %.2f h (máx %s)\n" "$delta" "$MAX"

# Validación
python - "$delta" "$MAX" <<'PY'
import sys
delta = float(sys.argv[1]); MAX = float(sys.argv[2])
ok = delta <= MAX + 0.01
print("RESULT:", "OK" if ok else "FAIL")
sys.exit(0 if ok else 2)
PY
