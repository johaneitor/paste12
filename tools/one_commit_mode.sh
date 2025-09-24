#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-chore: update}"
# Backup del HEAD previo (por si hay que volver)
if git rev-parse --verify HEAD >/dev/null 2>&1; then
  PREV="$(git rev-parse HEAD)"
  BK="backup-$(date -u +%Y%m%d-%H%M%SZ)-$PREV"
  git branch "$BK" >/dev/null 2>&1 || true
  git tag -f "prepush/$PREV" "$PREV" >/dev/null 2>&1 || true
fi

git add -A
if git rev-parse --verify HEAD >/dev/null 2>&1; then
  # Amenda el último commit (no se acumulan commits)
  if git diff --cached --quiet; then
    echo "No hay cambios para commitear."; 
  else
    git commit --amend -m "$MSG"
  fi
else
  git commit -m "$MSG"
fi

# Verificación mínima de sintaxis python (ajustá a tus paths)
python - <<'PY'
import py_compile, pathlib, sys
roots = [pathlib.Path("wsgiapp/__init__.py")]
for p in roots:
    py_compile.compile(str(p), doraise=True)
print("✓ py_compile OK")
PY

# Push como “un solo commit” y con lease (protege de over-write accidental)
git push --force-with-lease origin HEAD:main

echo
echo "✓ Push hecho en modo 'un solo commit'."
[ -n "${BK:-}" ] && echo "Revertir rápido: git checkout $BK && git reset --hard $BK"
echo "Tag previo: git show prepush/$PREV"
