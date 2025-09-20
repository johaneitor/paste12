#!/usr/bin/env bash
set -euo pipefail

# Mensaje de commit (env MSG="" o primer argumento)
MSG="${MSG:-${1:-ops: backend contract v6 (CORS 204, Link, FORM→JSON) + test exec}}"

# Archivos objetivo (se fuerzan aunque algunos tools estén ignorados)
FILES=(
  contract_shim.py
  wsgi.py
  wsgiapp/__init__.py
  tools/stabilize_backend_contract_v6.sh
  tools/test_exec_backend_v6.sh
  tools/git_push_backend_v6.sh
)

echo "→ Rama actual: $(git rev-parse --abbrev-ref HEAD)"
echo "→ Remoto: "; git remote -v | sed 's/^/   /'

# Bloqueo defensivo: no permitir workflows desde este entorno
if git status --porcelain | awk '{print $2}' | grep -q '^\.github/workflows/'; then
  echo "✗ No se permiten cambios en .github/workflows/ desde este entorno."
  echo "  (Usá otro entorno/SSH con token de 'workflow' si es intencional)."
  exit 1
fi

# Stage selectivo (forzado para esquivar .gitignore solo en estos paths)
added_any=0
for f in "${FILES[@]}"; do
  if [ -e "$f" ]; then
    git add -f "$f" && added_any=1 || true
  fi
done

# Si no se agregó nada, intentar detectar cambios y avisar
if [ "$added_any" -eq 0 ]; then
  if [ -n "$(git status --porcelain)" ]; then
    echo "ℹ️  No había cambios en los archivos objetivo. Hagamos un add general seguro…"
    git add -u
  else
    echo "✓ No hay cambios para commitear."
    exit 0
  fi
fi

# Gate rápido de sintaxis Python
echo "== prepush gate =="
python - <<'PY'
import py_compile, sys
ok=1
for p in ("contract_shim.py","wsgi.py","wsgiapp/__init__.py"):
    try:
        py_compile.compile(p, doraise=True)
        print(f"✓ py_compile {p}")
    except Exception as e:
        ok=0; print(f"✗ py_compile {p}: {e}")
sys.exit(0 if ok else 1)
PY

# Commit
git commit -m "$MSG" || { echo "ℹ️  Nada para commitear"; exit 0; }

# Push
git push origin main

echo
echo "✓ Push realizado."
echo "Siguiente paso sugerido en Render:"
echo "  Start Command:"
echo "    gunicorn wsgi:application --chdir /opt/render/project/src -w \${WEB_CONCURRENCY:-2} -k gthread --threads \${THREADS:-4} --timeout \${TIMEOUT:-120} -b 0.0.0.0:\$PORT"
echo "  * Sin variables APP_MODULE / P12_WSGI_*"
echo "  * Clear build cache + Deploy"
