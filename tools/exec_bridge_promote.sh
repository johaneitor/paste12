#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$(pwd)}"; cd "$ROOT"
RENDER_URL="${RENDER_URL:-https://paste12-rmsk.onrender.com}"
SLEEP_SECS="${SLEEP_SECS:-20}"

echo "[+] Ejecutando parche: tools/bridge_promote_db.sh"
if [ ! -x tools/bridge_promote_db.sh ]; then
  echo "[i] Haciendo ejecutable tools/bridge_promote_db.sh"
  chmod +x tools/bridge_promote_db.sh
fi
tools/bridge_promote_db.sh

echo
echo "[i] Verificá en Render que exista la variable DATABASE_URL (Postgres)."
echo "    (Opcional) Para permitir shim temporalmente: BRIDGE_ALLOW_SHIM=1"
echo "[i] Si Render hace auto-redeploy por push, espero ${SLEEP_SECS}s…"
sleep "${SLEEP_SECS}"

echo
echo "[+] Health remoto:"
curl -sS "${RENDER_URL}/api/health" || true
echo

echo "[+] URL map (debug):"
curl -sS "${RENDER_URL}/api/debug-urlmap" | sed -e 's/{/{\n/g' -e 's/}/\n}/g' || true
echo

echo "[+] Smoke GET /api/notes?page=1"
curl -i -sS "${RENDER_URL}/api/notes?page=1" | sed -n '1,120p' || true
echo

echo "[+] Smoke POST /api/notes"
curl -i -sS -X POST -H 'Content-Type: application/json' \
  -d '{"text":"remote-db","hours":24}' \
  "${RENDER_URL}/api/notes" | sed -n '1,160p' || true
echo

echo "[✓] Listo. Si /api/notes sigue en 500 y el detalle dice SQLAlchemy/app no registrada,"
echo "    revisá DATABASE_URL (corrige postgres:// → postgresql://) y redeploy manual."
