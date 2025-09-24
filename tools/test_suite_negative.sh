#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }
sect(){ printf "\n== %s ==\n" "$*"; }

sect "POST vacío (FORM)"
curl -sS -i -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode "text=" "$BASE/api/notes" | sed -n '1,12p'

sect "POST vacío (JSON)"
curl -sS -i -H 'Content-Type: application/json' \
  --data '{}' "$BASE/api/notes" | sed -n '1,12p'

sect "Like/View inexistente"
curl -sS -i -X POST "$BASE/api/notes/999999/like" | sed -n '1,12p'
curl -sS -i -X POST "$BASE/api/notes/999999/view" | sed -n '1,12p'

sect "Método no permitido"
curl -sS -i -X PUT "$BASE/api/notes" | sed -n '1,12p'

sect "CORS simple GET"
curl -sS -i -H 'Origin: https://example.com' "$BASE/api/health" | sed -n '1,20p'
