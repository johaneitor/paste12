#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"

echo "[+] Escribiendo wsgiapp/__init__.py (shim robusto → usa wsgi:app y fuerza /api/* si faltan)"
mkdir -p wsgiapp
cat > wsgiapp/__init__.py <<'PY'
from importlib import import_module
from flask import Blueprint, jsonify

# Importa tu wsgi.py real y reexporta su 'app'
_w = import_module("wsgi")
app = getattr(_w, "app")

def _has(rule: str, method: str | None = None) -> bool:
    try:
        for r in app.url_map.iter_rules():
            if str(r) == rule:
                if method is None:
                    return True
                return method in r.methods
    except Exception:
        pass
    return False

# 1) Garantizar /api/notes GET/POST (reusa bp_forced si existe en wsgi.py)
if (not _has("/api/notes", "GET")) or (not _has("/api/notes", "POST")):
    bp_forced = getattr(_w, "bp_forced", None)
    if bp_forced is not None:
        try:
            app.register_blueprint(bp_forced, url_prefix="/api")
        except Exception:
            # si ya estaba registrado o cualquier otra cosa, seguimos
            pass

# 2) Agregar /api/debug-urlmap si falta (útil para verificar qué cargó)
if not _has("/api/debug-urlmap", "GET"):
    dbg = Blueprint("shim_dbg", __name__)
    @dbg.get("/debug-urlmap")
    def _debug_urlmap():
        rules = []
        for r in app.url_map.iter_rules():
            methods = sorted([m for m in r.methods if m not in ("HEAD","OPTIONS")])
            rules.append({"rule": str(r), "endpoint": r.endpoint, "methods": methods})
        return jsonify({"rules": rules, "source": "wsgiapp-shim"})
    try:
        app.register_blueprint(dbg, url_prefix="/api")
    except Exception:
        pass

# 3) Health check propio si no existe
if not _has("/api/health", "GET"):
    hb = Blueprint("shim_health", __name__)
    @hb.get("/health")
    def _health():
        return jsonify(ok=True, note="wsgiapp-shim")
    try:
        app.register_blueprint(hb, url_prefix="/api")
    except Exception:
        pass

# 4) Asegurar create_all si wsgi.py expone 'db'
_db = getattr(_w, "db", None)
if _db is not None:
    try:
        with app.app_context():
            _db.create_all()
    except Exception:
        pass
PY

echo "[+] Commit & push"
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
git add -A
git commit -m "wsgiapp shim robusto: reexporta wsgi:app + fuerza /api/notes/debug-urlmap/health y create_all()" || true
git push -u --force-with-lease origin "$BRANCH"

echo
echo "[i] Mantén el Start Command en Render como:"
echo "    gunicorn -w \${WEB_CONCURRENCY:-2} -k gthread --threads \${THREADS:-4} -b 0.0.0.0:\$PORT wsgiapp:app"
echo "[i] Redeploy y verifica:"
echo "    curl -s https://paste12-rmsk.onrender.com/api/health"
echo "    curl -s https://paste12-rmsk.onrender.com/api/debug-urlmap | jq ."
echo "    curl -i -s 'https://paste12-rmsk.onrender.com/api/notes?page=1' | sed -n '1,80p'"
echo "    curl -i -s -X POST -H 'Content-Type: application/json' -d '{\"text\":\"remote-ok\",\"hours\":24}' https://paste12-rmsk.onrender.com/api/notes | sed -n '1,120p'"
