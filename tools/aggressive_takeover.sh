#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d-%H%M%SZ)"

# 1) Respaldos de blueprint/Procfile si existen
for f in render.yaml render.yml Procfile start_render.sh; do
  if [ -f "$f" ]; then
    mv -v "$f" "${f}.bak.${ts}"
  fi
done

# 2) Entry WSGI determinista (raíz del repo)
cat > wsgi.py <<'PY'
# wsgi.py — entrypoint determinista para Gunicorn (Render)
# Intenta backend.create_app() y cae a wsgiapp._resolve_app() sólo si hace falta.
from typing import Any, Callable

application = None  # type: ignore
app = None          # alias

try:
    # Camino moderno (si existe backend con factoría)
    from backend import create_app as _factory  # type: ignore
    application = _factory()                     # Flask app / WSGI callable
except Exception:
    try:
        # Fallback: usa el resolutor interno si está presente
        from wsgiapp import _resolve_app  # type: ignore
        application = _resolve_app()
    except Exception as e:  # pragma: no cover
        # Dejar trazas claras si algo va mal
        import sys, traceback
        print("[wsgi] FATAL: no pude construir la app WSGI", file=sys.stderr)
        traceback.print_exc()

# Exportar alias 'app' además de 'application' (soporta wsgi:app o wsgi:application)
app = application  # type: ignore
PY

python - <<'PY'
import py_compile; py_compile.compile('wsgi.py', doraise=True)
print("✓ py_compile wsgi.py OK")
PY

git add -A
git commit -m "ops: takeover de start (wsgi:application) y backup de blueprint/Procfile"
git push origin main

echo
echo "➡️  En Render (Dashboard → Settings):"
echo "    Start Command ="
echo "      gunicorn wsgi:application --chdir /opt/render/project/src -w \${WEB_CONCURRENCY:-2} -k gthread --threads \${THREADS:-4} --timeout \${TIMEOUT:-120} -b 0.0.0.0:\$PORT"
echo "    Luego: Clear build cache → Save, rebuild, and deploy."
echo
echo "⚠️  Asegurate de NO tener variables APP_MODULE ni P12_WSGI_* en Environment."
