#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"

echo "[+] Creando paquete 'wsgiapp' que reexporta app desde wsgi.py"
mkdir -p wsgiapp
cat > wsgiapp/__init__.py <<'PY'
# Paquete shim: si gunicorn arranca wsgiapp:app, redirigimos al app de wsgi.py
from importlib import import_module

_w = import_module("wsgi")        # importa el módulo wsgi.py del repo
app = getattr(_w, "app")          # reexporta app (gunicorn verá wsgiapp:app)

# (Opcional) asegura que /api/notes exista si el app aún no lo registró
try:
    has_notes = any(str(r.rule) == "/api/notes" for r in app.url_map.iter_rules())
    if not has_notes and hasattr(_w, "bp_forced"):
        app.register_blueprint(getattr(_w, "bp_forced"), url_prefix="/api")
except Exception:
    pass
PY

echo "[+] Commit & push"
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
git add -A
git commit -m "wsgiapp shim: route wsgiapp:app to wsgi:app (forced /api/notes fallback)" || true
git push -u --force-with-lease origin "$BRANCH"

echo
echo "[i] Mantén Start Command en Render como:"
echo "    gunicorn -w \${WEB_CONCURRENCY:-2} -k gthread --threads \${THREADS:-4} -b 0.0.0.0:\$PORT wsgiapp:app"
echo "    Redeploy y luego verifica con:"
echo "    bash tools/verify_remote_is_wsgi.sh"
