#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL}"
TMP="${HOME%/}/tmp/check_headers_$$"
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT

echo "== HEADERS / CORS / RATE (GET) =="
echo "curl -si \"$BASE/api/notes?limit=1\" | sed -n '1,30p'"
curl -si "$BASE/api/notes?limit=1" 2>/dev/null | sed -n '1,30p' || echo "ERROR: fallo curl GET /api/notes"

echo
echo "== PRE-FLIGHT OPTIONS =="
echo "curl -si -X OPTIONS \"$BASE/api/notes\" | sed -n '1,30p'"
curl -si -X OPTIONS "$BASE/api/notes" 2>/dev/null | sed -n '1,30p' || echo "ERROR: fallo curl OPTIONS /api/notes"

echo
echo "== HEALTH DB =="
echo "curl -si \"$BASE/api/health/db\" | sed -n '1,200p'"
curl -si "$BASE/api/health/db" 2>/dev/null | sed -n '1,200p' || echo "WARN: /api/health/db no responde o devuelve !=200"
