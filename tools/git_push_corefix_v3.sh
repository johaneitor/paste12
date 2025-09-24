#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: corefix - stage deletions + add new tools + pooling_guard + sanity}"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "ERROR: no es repo git"; exit 2; }

echo "== Stage deletions/modificaciones =="
git add -u

echo "== Force-add tools/*.sh (ignorado por .gitignore) =="
shopt -s nullglob
for f in tools/*.sh; do git add -f "$f" || true; done
# incluye cuarentena si existe
if [[ -d tools/__quarantine__ ]]; then
  git add -f tools/__quarantine__/* 2>/dev/null || true
fi

echo "== Añadir backend/pooling_guard.py si existe =="
[[ -f backend/pooling_guard.py ]] && git add -f backend/pooling_guard.py || true

echo "== Sanity Python (py_compile) =="
py_files=()
[[ -f backend/__init__.py ]] && py_files+=("backend/__init__.py")
[[ -f backend/routes.py   ]] && py_files+=("backend/routes.py")
[[ -f backend/models.py   ]] && py_files+=("backend/models.py")
[[ -f wsgi.py             ]] && py_files+=("wsgi.py")
[[ -f contract_shim.py    ]] && py_files+=("contract_shim.py")

if ((${#py_files[@]})); then
  python - "${py_files[@]}" <<'PY'
import py_compile, sys
files = sys.argv[1:]
ok = True
for p in files:
    try:
        py_compile.compile(p, doraise=True)
        print("✓ py_compile", p, "OK")
    except Exception as e:
        ok = False
        print("✗ py_compile FAIL:", p, "-", repr(e))
if not ok:
    sys.exit(3)
PY
fi

echo "== Commit =="
if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada para commitear"
fi

echo "== Push =="
git push -u origin main

echo "== HEADs =="
echo "Local : $(git rev-parse HEAD)"
up="$(git rev-parse @{u} 2>/dev/null || true)"
[[ -n "$up" ]] && echo "Remote: $up" || echo "Remote: (upstream recién configurado)"
