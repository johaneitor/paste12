#!/usr/bin/env bash
set -euo pipefail
git stash push -u -m "pre-push-clean $(date -u +%FT%TZ)" >/dev/null 2>&1 || true
git fetch origin --prune
BASE=origin/main
RANGE="$BASE..HEAD"
if [ -z "$(git rev-list $RANGE 2>/dev/null)" ]; then
  git push origin main || true; exit 0
fi
mapfile -t ALL < <(git rev-list --reverse "$RANGE")
PICK=()
for c in "${ALL[@]}"; do
  if git diff-tree --no-commit-id --name-only -r "$c" | grep -qE '^\.github/workflows/'; then
    echo "saltando $c (workflows)"
  else
    PICK+=("$c")
  fi
done
BACKUP="backup-$(date +%Y%m%d-%H%M%S)-$(git rev-parse --short HEAD)"
git branch "$BACKUP" >/dev/null 2>&1 || true
git checkout -B main "$BASE" >/dev/null 2>&1
git reset --hard "$BASE"
for c in "${PICK[@]}"; do git cherry-pick -x "$c" || { echo "✗ conflicto en $c"; exit 2; }; done
python - <<'PY'
import os, py_compile
p="wsgiapp/__init__.py"
if os.path.exists(p):
  py_compile.compile(p, doraise=True)
print("✓ py_compile OK")
PY
git push origin main
echo "✓ push OK (sin workflows). Backup: $BACKUP"
