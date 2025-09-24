#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"

echo "[*] /api/health:"
HEALTH="$(curl -s "$BASE/api/health" || true)"
echo "$HEALTH"

NOTE_VAL="$(printf '%s' "$HEALTH" | sed -n 's/.*"note":"\([^"]*\)".*/\1/p')"
echo "[i] note=$NOTE_VAL (esperado: 'wsgi' si está cargado wsgi:app; 'wsgiapp' si sigue wsgiapp:app)"

echo
echo "[*] /api/debug-urlmap (debe existir con wsgi:app):"
curl -s "$BASE/api/debug-urlmap" | python -m json.tool 2>/dev/null || echo "(no JSON → probablemente 404 → aún no es wsgi:app)"

echo
echo "[*] GET /api/notes:"
curl -i -s "$BASE/api/notes?page=1" | sed -n '1,60p'

echo
echo "[*] POST /api/notes:"
curl -i -s -X POST -H 'Content-Type: application/json' -d '{"text":"hello-remote","hours":24}' "$BASE/api/notes" | sed -n '1,120p'
