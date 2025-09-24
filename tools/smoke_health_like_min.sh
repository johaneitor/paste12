#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"
echo "== /api/health =="; curl -sI "$BASE/api/health" | sed -n '1p'
echo "== POST /api/notes (JSON) =="
NEW="$(
  jq -n --arg t "smoke $(date -u +%H:%M:%SZ) texto largo para validar 1234567890 abcdefghij" '{text:$t}' \
  | curl -fsS -H 'Content-Type: application/json' --data-binary @- "$BASE/api/notes" | jq -r '.item.id'
)"; echo "note: ${NEW:-<fail>}"
[ -n "${NEW:-}" ] || { echo "✗ no se creó nota"; exit 1; }
echo "== POST /api/notes/:id/like ==";
curl -sS -X POST "$BASE/api/notes/$NEW/like" | jq -r '.ok,.id,.likes' 2>/dev/null || true
