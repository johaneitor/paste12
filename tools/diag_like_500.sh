#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"
ID="${2:?Uso: $0 https://host NOTE_ID}"
echo "== POST /api/notes/$ID/like (raw) =="
curl -sS -i -X POST "$BASE/api/notes/$ID/like"
echo
