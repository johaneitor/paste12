#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }
echo "== /api/health =="; curl -sS -i "$BASE/api/health" | sed -n '1,80p'
echo "---------------------------------------------"
echo "== /api/notes?limit=5 (con cuerpo aunque sea 500) =="
curl -sS -i "$BASE/api/notes?limit=5" || true
echo
echo "---------------------------------------------"
echo "== /api/notes_fallback?limit=5 (si existe) =="
curl -sS -i "$BASE/api/notes_fallback?limit=5" || true
echo
