#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-${BASE:-https://paste12-rmsk.onrender.com}}"
echo "== smoke_all @ $BASE =="
tools/smoke_front.sh "$BASE"
tools/smoke_api.sh   "$BASE"
echo "✅ smoke_all OK"
