#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"

echo "[+] Backup de wsgiapp.py (si existe)"
[ -f wsgiapp.py ] && cp -f wsgiapp.py "wsgiapp.py.bak.$(date +%s)" || true

echo "[+] Escribiendo wsgiapp.py (bridge → reexporta wsgi:app y fuerza /api/debug-urlmap si falta)"
cat > wsgiapp.py <<'PY'
from importlib import import_module
from flask import Blueprint, jsonify

# Reexporta la app real desde wsgi.py
_w = import_module("wsgi")
app = getattr(_w, "app")

def _has(rule: str, method: str | None = None) -> bool:
    try:
        for r in app.url_map.iter_rules():
            if str(r) == rule:
                return True if method is None else method in r.methods
    except Exception:
        pass
    return False

# Si /api/debug-urlmap no existe, lo agregamos
if not _has("/api/debug-urlmap", "GET"):
    dbg = Blueprint("wsgiapp_bridge_dbg", __name__)
    @dbg.get("/debug-urlmap")
    def _debug_urlmap():
        rules = []
        for r in app.url_map.iter_rules():
            methods = sorted([m for m in r.methods if m not in ("HEAD","OPTIONS")])
            rules.append({"rule": str(r), "endpoint": r.endpoint, "methods": methods})
        return jsonify({"rules": rules, "source": "wsgiapp-bridge"})
    try:
        app.register_blueprint(dbg, url_prefix="/api")
    except Exception:
        pass
PY

echo "[+] Commit & push"
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
git add -A
git commit -m "wsgiapp.py → bridge: reexport wsgi:app y fuerza /api/debug-urlmap" || true
git push -u --force-with-lease origin "$BRANCH"

echo
echo "[i] En Render deja el Start Command como:"
echo "    gunicorn -w \${WEB_CONCURRENCY:-2} -k gthread --threads \${THREADS:-4} -b 0.0.0.0:\$PORT wsgiapp:app"
echo
echo "[i] Tras el redeploy, verificá:"
echo "    curl -s https://paste12-rmsk.onrender.com/api/health"
echo "    curl -s https://paste12-rmsk.onrender.com/api/debug-urlmap | jq ."
echo "    curl -i -s 'https://paste12-rmsk.onrender.com/api/notes?page=1' | sed -n '1,80p'"
echo "    curl -i -s -X POST -H 'Content-Type: application/json' -d '{\"text\":\"remote-ok\",\"hours\":24}' \\"
echo "         https://paste12-rmsk.onrender.com/api/notes | sed -n '1,120p'"
