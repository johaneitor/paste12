#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"
MAX="${2:-2160}"

note_json="$(curl -fsS -X POST "$BASE/api/notes" \
  -H 'Content-Type: application/json' \
  -d '{"text":"ttl cap test","hours":99999}')"

id="$(printf '%s' "$note_json" | jq -r '.item.id')"
ts="$(printf '%s' "$note_json" | jq -r '.item.timestamp')"
exp="$(printf '%s' "$note_json" | jq -r '.item.expires_at')"
likes="$(printf '%s' "$note_json" | jq -r '.item.likes // 0')"

python - "$ts" "$exp" "$MAX" <<'PY'
import sys, datetime as dt
from dateutil import parser
ts = parser.isoparse(sys.argv[1])
ex = parser.isoparse(sys.argv[2])
maxh = int(sys.argv[3])
delta_h = (ex - ts).total_seconds()/3600.0
print(f"TTL horas calculado: {delta_h:.2f}h (máx {maxh})")
print("OK" if delta_h <= maxh+0.01 else "FAIL")
PY
echo "note id: $id   likes: $likes"
