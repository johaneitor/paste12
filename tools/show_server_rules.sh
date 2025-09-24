#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
echo "== reglas @ $BASE =="
if curl -sS -f "$BASE/__whoami" | python -m json.tool >/dev/null 2>&1; then
  curl -sS "$BASE/__whoami" | python -m json.tool \
    | sed -n 's/.*"rule": "\(.*\)".*/\1/p' | sort
else
  curl -sS "$BASE/api/_routes" | python -m json.tool 2>/dev/null \
    | sed -n 's/.*"rule": "\(.*\)".*/\1/p' | sort || true
fi
