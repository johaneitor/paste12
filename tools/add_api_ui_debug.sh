#!/usr/bin/env bash
set -Eeuo pipefail
ROUTES="backend/routes.py"

echo "➤ Backup"
cp -f "$ROUTES" "$ROUTES.bak.$(date +%s)" 2>/dev/null || true

python - <<'PY'
from pathlib import Path
p = Path("backend/routes.py")
s = p.read_text(encoding="utf-8")
block = r'''
# --- UI debug mount under /api/ui/* (no depende del blueprint webui) ---
try:
    from flask import send_from_directory
    from backend.webui import FRONT_DIR as _FD  # dónde están los archivos del frontend

    @api.route("/ui", methods=["GET"])               # -> /api/ui
    def ui_index():
        return send_from_directory(_FD, "index.html")

    @api.route("/ui/js/<path:fname>", methods=["GET"])
    def ui_js(fname):
        return send_from_directory(_FD / "js", fname)

    @api.route("/ui/css/<path:fname>", methods=["GET"])
    def ui_css(fname):
        return send_from_directory(_FD / "css", fname)

    @api.route("/ui/robots.txt", methods=["GET"])
    def ui_robots():
        p = _FD / "robots.txt"
        return (send_from_directory(_FD, "robots.txt") if p.exists() else ("", 204))

    @api.route("/ui/favicon.ico", methods=["GET"])
    def ui_favicon():
        p = _FD / "favicon.ico"
        return (send_from_directory(_FD, "favicon.ico") if p.exists() else ("", 204))
except Exception:
    # No rompemos el API si algo falla
    pass
'''
if "/ui\", methods=[\"GET\"]" in s or "def ui_index(" in s:
    print("Bloque /api/ui/* ya presente (ok).")
else:
    if not s.endswith("\n"): s += "\n"
    s += block + "\n"
    p.write_text(s, encoding="utf-8")
    print("Bloque /api/ui/* agregado.")
PY

echo "➤ Commit & push"
git add backend/routes.py
git commit -m "feat(debug): exponer frontend en /api/ui/* para diagnosticar Render" || true
git push origin main
