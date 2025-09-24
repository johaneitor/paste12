#!/usr/bin/env bash
set -euo pipefail
PORT="${PORT:-8000}"
BASE="http://127.0.0.1:$PORT"

echo "[+] 1) /api/health"
curl -s "$BASE/api/health" || echo "{}"

echo "[+] 2) Crear nota"
NEW=$(curl -s -X POST -H "Content-Type: application/json" \
  -d '{"text":"e2e-interactions","hours":24}' \
  "$BASE/api/notes")
echo "$NEW"
NOTE_ID=$(echo "$NEW" | sed -n 's/.*"id":[[:space:]]*\([0-9]\+\).*/\1/p')
[ -n "${NOTE_ID:-}" ] || { echo "[!] No pude obtener NOTE_ID"; exit 1; }
echo "NOTE_ID=$NOTE_ID"

echo "[+] 3) Like idempotente"
echo "    3.1) Like #1"
curl -i -s -X POST "$BASE/api/notes/$NOTE_ID/like" | sed -n '1,40p'
echo "    3.2) Like #2 (no debe subir de 1)"
curl -i -s -X POST "$BASE/api/notes/$NOTE_ID/like" | sed -n '1,40p'

echo "[+] 4) View con ventana 15m"
echo "    4.1) View #1"
curl -i -s -X POST "$BASE/api/notes/$NOTE_ID/view" | sed -n '1,40p'
echo "    4.2) View #2 (misma ventana; contador no debería subir más de 1 por fp)"
curl -i -s -X POST "$BASE/api/notes/$NOTE_ID/view" | sed -n '1,40p'

echo "[+] 5) Stats"
curl -i -s "$BASE/api/notes/$NOTE_ID/stats" | sed -n '1,120p'

echo "[+] 6) Listado"
curl -i -s "$BASE/api/notes?page=1" | sed -n '1,120p'

echo "[✓] E2E listo."
