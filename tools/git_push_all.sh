#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
MSG="${1:-chore: bulk fixes (endpoints/routes/limiter/doctor)}"

if [ ! -d .git ]; then
  echo "[!] No es un repo Git aquí."
  exit 1
fi

BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
git add -A
git commit -m "$MSG" || true
echo "[i] Pushing a origin/$BRANCH ..."
git push -u --force-with-lease origin "$BRANCH"
echo "[✓] Push OK"
