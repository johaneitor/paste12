#!/usr/bin/env bash
set -Eeuo pipefail

INIT="backend/__init__.py"

echo "➤ Backup"
cp -f "$INIT" "$INIT.bak.$(date +%s)" 2>/dev/null || true

python - <<'PY'
from pathlib import Path, re
p = Path("backend/__init__.py")
s = p.read_text(encoding="utf-8")

# Evitar duplicados: si ya existe el bloque, no lo volvemos a insertar
already = ("FRONT_DIR" in s) and ('@app.route("/", methods=["GET"])' in s)

if not already:
    block = r"""
# === Frontend routes (index + js) ===
try:
    from flask import send_from_directory
    from pathlib import Path as _Path
    _PKG_DIR = _Path(__file__).resolve().parent  # .../backend
    FRONT_DIR = (_PKG_DIR.parent / "frontend").resolve()

    @app.route("/", methods=["GET"])
    def root_index():
        return send_from_directory(FRONT_DIR, "index.html")

    @app.route("/js/<path:fname>", methods=["GET"])
    def serve_js(fname):
        return send_from_directory(FRONT_DIR / "js", fname)

    @app.route("/favicon.ico", methods=["GET"])
    def favicon_ico():
        p = FRONT_DIR / "favicon.ico"
        if p.exists():
            return send_from_directory(FRONT_DIR, "favicon.ico")
        return ("", 204)
except Exception:
    # Si no hay frontend en el deploy, no romper el API
    pass
"""
    if not s.endswith("\n"):
        s += "\n"
    s += block + "\n"
    p.write_text(s, encoding="utf-8")
    print("init: rutas frontend añadidas.")
else:
    print("init: rutas frontend ya presentes; no se cambia nada.")
PY

echo "➤ Commit & push"
git add backend/__init__.py || true
git commit -m "fix(web): servir index y JS desde Flask usando FRONT_DIR relativo al paquete (evita 404 en /)" || true
git push origin main

echo "✓ Listo."
