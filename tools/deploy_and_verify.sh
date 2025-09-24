#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"
RENDER_URL="${RENDER_URL:-https://paste12-rmsk.onrender.com}"
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"

git add -A
git commit -m "deploy: ensure wsgi registers API; add backend/api fallback; auto-create DB" || true
git push -u --force-with-lease origin "$BRANCH"

echo "[i] Esperando 12s..."
sleep 12

echo "[+] /api/health"
curl -i -s "${RENDER_URL}/api/health" | sed -n '1,60p'; echo
echo "[+] GET /api/notes"
curl -i -s "${RENDER_URL}/api/notes?page=1" | sed -n '1,80p'; echo
echo "[+] POST /api/notes"
curl -i -s -X POST -H "Content-Type: application/json" \
  -d '{"text":"remote-ok","hours":24}' \
  "${RENDER_URL}/api/notes" | sed -n '1,120p'; echo
