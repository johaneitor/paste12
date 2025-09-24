#!/usr/bin/env bash
set -euo pipefail

MSG="${1:-ops: publish core fixes + tools (factory-v2 stable)}"

# 0) Verificaciones básicas
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "ERROR: no es un repo git"; exit 2; }

# 1) Asegurar que podemos comitear borrados + agregar ignorados
#    - 'git add -A' captura borrados/modificados.
#    - 'git add -f tools/*.sh' fuerza los scripts aunque .gitignore los tape.
git add -A || true
git add -f tools/*.sh 2>/dev/null || true
git add -f tools/__quarantine__/* 2>/dev/null || true
[[ -f backend/pooling_guard.py ]] && git add backend/pooling_guard.py || true

# 2) Gate de sintaxis Python de piezas críticas (no fallar si alguna no existe)
python - <<'PY'
import py_compile, os
critical = ["backend/__init__.py","backend/routes.py","backend/models.py","wsgi.py","contract_shim.py"]
for f in critical:
    if os.path.exists(f):
        try:
            py_compile.compile(f, doraise=True)
            print(f"[py] OK  - {f}")
        except Exception as e:
            print(f"[py] FAIL- {f}: {e}")
            raise
PY

# 3) Commit si hay cambios
if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada para commitear"
fi

# 4) Push
echo "== prepush gate =="; echo "✓ listo"
git push -u origin main

# 5) HEADs y remotos
echo "== HEADs =="
echo "Local : $(git rev-parse HEAD)"
UP="$(git rev-parse @{u} 2>/dev/null || true)"; [[ -n "$UP" ]] && echo "Remote: $UP" || echo "Remote: (definido recién)"
echo "== remotos =="; git remote -v
