#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-${BASE:-https://paste12-rmsk.onrender.com}}"

echo "== smoke_view @ $BASE =="
mktempjson() { mktemp 2>/dev/null || mktemp -t tmp; }
H="$(mktempjson)"; B="$(mktempjson)"; trap 'rm -f "$H" "$B"' EXIT

req() {
  local method="$1" path="$2" data="${3:-}"
  : >"$H"; : >"$B"
  if [[ -n "$data" ]]; then
    code=$(curl -sS -D "$H" -o "$B" -X "$method" -H 'Content-Type: application/json' --data "$data" "$BASE$path" -w '%{http_code}')
  else
    code=$(curl -sS -D "$H" -o "$B" -X "$method" "$BASE$path" -w '%{http_code}')
  fi
  printf "%s" "$code"
}

pp() { python -m json.tool < "$B" 2>/dev/null || head -c 400 "$B"; echo; }

# Crear nota
ts=$(date -u +%FT%TZ)
data=$(printf '{"text":"smoke view %s","hours":24}' "$ts")
c=$(req POST /api/notes "$data"); echo "-- create -> $c"; pp
[[ "$c" == 201 ]] || { echo "FAIL create"; exit 1; }

ID="$(python -c 'import json,sys;print(json.load(open(sys.argv[1]))["id"])' "$B" 2>/dev/null || true)"
[[ -n "$ID" ]] || { echo "FAIL sin ID"; exit 1; }
echo "ID=$ID"

# POST /view
c=$(req POST "/api/notes/$ID/view"); echo "-- view -> $c"; pp
[[ "$c" == 200 ]] || { echo "FAIL /view !=200"; exit 1; }

# Ver contadores
c=$(req GET "/api/notes/$ID"); echo "-- get -> $c"; pp
exit 0
