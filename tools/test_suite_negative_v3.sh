#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }
echo "== POST vacío (FORM) ==";  curl -sS -i -H 'Content-Type: application/x-www-form-urlencoded' "$BASE/api/notes" --data '' | sed -n '1,12p'
echo "== POST vacío (JSON) ==";  curl -sS -i -H 'Content-Type: application/json'              "$BASE/api/notes" --data '{}' | sed -n '1,12p'
echo "== Like/View/Report inexistente (espera 404) =="
for ep in like view report; do
  code=$(curl -sS -o /dev/null -w "%{http_code}" -X POST "$BASE/api/notes/999999/$ep")
  printf " %-6s 999999 => %s\n" "$ep" "$code"
done
