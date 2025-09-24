#!/usr/bin/env bash
set -euo pipefail

for f in wsgi.py run.py render_entry.py; do
  [ -f "$f" ] || continue
  echo "[*] Corrigiendo $f"
  sed -i 's/from backend.modules.interactions import interactions_bp/from backend.modules.interactions import bp as interactions_bp, alias_bp/' "$f"
done

echo "[+] Commit & push"
git add -A
git commit -m "fix: register correct bp + alias for interactions" || true
git push -u --force-with-lease origin "$(git rev-parse --abbrev-ref HEAD)"
