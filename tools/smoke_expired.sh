#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
_red(){ printf "\033[31m%s\033[0m\n" "$*"; }
_grn(){ printf "\033[32m%s\033[0m\n" "$*"; }
echo "== smoke_expired @ $BASE =="

NEW="$(curl -sS -H 'Content-Type: application/json' --data '{"text":"expire-now","hours":0}' "$BASE/api/notes")"
ID="$(BODY="$NEW" python - <<'PY'
import os, json; print(json.loads(os.environ["BODY"])["id"])
PY
)"
[[ -n "$ID" ]] || { _red "no pude crear nota hours=0"; echo "$NEW"; exit 1; }

LIST="$(curl -sS "$BASE/api/notes?active_only=1&limit=50")"
if echo "$LIST" | grep -q "\"id\": *$ID"; then
  _red "La nota expirada aparece en activos"
  echo "$LIST" | head -n 20
  exit 1
fi
_grn "✅ smoke_expired OK (ID=$ID fuera del listado activo)"
