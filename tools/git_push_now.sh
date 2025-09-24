#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: ejecutores v8 + exportador v2}"
# Archivos que queremos asegurar en el repo:
want=$(cat <<'L'
tools/test_exec_backend_v8.sh
tools/download_results_texts_v2.sh
tools/git_push_backend_v9.sh
tools/verify_push_state.sh
L
)

echo "== Staging (forzado por si .gitignore los oculta) =="
while read -r f; do
  [[ -z "$f" ]] && continue
  if [[ -f "$f" ]]; then
    git add -f "$f"
    echo "  + staged $f"
  else
    echo "  - no existe $f (omitido)"
  fi
done <<< "$want"

echo
git status --porcelain

# Commit si hay algo staged
if ! git diff --cached --quiet; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada que commitear (index vacío)"
fi

# Push y reporte
git push -u origin HEAD:main
echo
echo "== Post-push =="
echo "  Local  HEAD : $(git rev-parse HEAD)"
echo "  Remote HEAD : $(git ls-remote origin -h refs/heads/main | cut -f1)"
