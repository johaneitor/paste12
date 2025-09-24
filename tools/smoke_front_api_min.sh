#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }
echo "== health =="; curl -fsS "$BASE/api/health"; echo
echo "== list =="; curl -fsS "$BASE/api/notes?limit=3"; echo
echo "== create =="; ID="$(printf '{"text":"ui shim smoke %s 1234567890"}' "$(date -u +%H:%M:%SZ)" | curl -fsS -H 'Content-Type: application/json' --data-binary @- "$BASE/api/notes" | { command -v jq >/dev/null && jq -r '.item.id // .id' || sed -n 's/.*"id": *\([0-9]\+\).*/\1/p'; })"; echo "id=$ID"
echo "== like =="; curl -fsS -X POST "$BASE/api/notes/$ID/like"; echo
