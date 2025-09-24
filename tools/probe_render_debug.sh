#!/usr/bin/env bash
set -Eeuo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
echo "BASE = $BASE"
echo
echo "--- __debug/routes ---"
curl -sS "$BASE/__debug/routes" | python -m json.tool | sed -n '1,120p' || true
echo
echo "--- __debug/fs?path=. ---"
curl -sS "$BASE/__debug/fs?path=." | python -m json.tool || true
echo
echo "--- __debug/fs?path=backend ---"
curl -sS "$BASE/__debug/fs?path=backend" | python -m json.tool || true
echo
echo "--- __debug/fs?path=backend/frontend ---"
curl -sS "$BASE/__debug/fs?path=backend/frontend" | python -m json.tool || true
