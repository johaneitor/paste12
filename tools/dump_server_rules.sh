#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"

echo "== dump_server_rules @ $BASE =="
if curl -sS -f "$BASE/__whoami" | python -m json.tool >/dev/null 2>&1; then
  echo "(via __whoami)"
  curl -sS "$BASE/__whoami" | python -m json.tool \
    | sed -n 's/.*"rule": "\(.*\)".*/\1/p' | sort
else
  echo "(no __whoami JSON) — probá /api/_routes si existe:"
  curl -sS "$BASE/api/_routes" | python -m json.tool 2>/dev/null \
    | sed -n 's/.*"rule": "\(.*\)".*/\1/p' | sort || true
fi
