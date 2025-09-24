#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"
ID=$(curl -fsS -X POST "$BASE/api/notes" -H 'content-type: application/json' \
  -d '{"text":"probe views"}' | sed -n 's/.*"id": *\([0-9]\+\).*/\1/p')
echo "Nueva nota id=$ID"

echo "Antes:"
curl -fsS "$BASE/api/notes/$ID" | sed -n '1,200p'

echo "Simulo vista (POST /view con X-FP=verify):"
curl -fsS -X POST "$BASE/api/notes/$ID/view" -H 'X-FP: verify' | sed -n '1,200p'

echo "Después:"
curl -fsS "$BASE/api/notes/$ID" | sed -n '1,200p'
