#!/usr/bin/env bash
set -Eeuo pipefail

echo "➤ Asegurar ensure_webui() en backend/webui.py"
python - <<'PY'
from pathlib import Path, re
p = Path("backend/webui.py")
s = p.read_text(encoding="utf-8")
# 1) FRONT_DIR robusto (si ya estaba, lo dejamos)
if "def _discover_front_dir" not in s:
    s = (
        "from flask import Blueprint, send_from_directory\n"
        "from pathlib import Path\n\n"
        "def _discover_front_dir():\n"
        "    pkg_dir = Path(__file__).resolve().parent\n"
        "    candidates = [\n"
        "        pkg_dir / 'frontend',\n"
        "        pkg_dir.parent / 'frontend',\n"
        "        Path.cwd() / 'frontend',\n"
        "    ]\n"
        "    for c in candidates:\n"
        "        if c.exists():\n"
        "            return c\n"
        "    return candidates[0]\n"
        "FRONT_DIR = _discover_front_dir()\n"
        "webui = Blueprint('webui', __name__)\n\n"
        "@webui.get('/')\n"
        "def index():\n"
        "    return send_from_directory(FRONT_DIR, 'index.html')\n\n"
        "@webui.get('/js/<path:fname>')\n"
        "def js(fname: str):\n"
        "    return send_from_directory(FRONT_DIR / 'js', fname)\n\n"
        "@webui.get('/css/<path:fname>')\n"
        "def css(fname: str):\n"
        "    return send_from_directory(FRONT_DIR / 'css', fname)\n\n"
        "@webui.get('/robots.txt')\n"
        "def robots():\n"
        "    p = FRONT_DIR / 'robots.txt'\n"
        "    return (send_from_directory(FRONT_DIR, 'robots.txt') if p.exists() else ('', 204))\n\n"
        "@webui.get('/favicon.ico')\n"
        "def favicon():\n"
        "    p = FRONT_DIR / 'favicon.ico'\n"
        "    return (send_from_directory(FRONT_DIR, 'favicon.ico') if p.exists() else ('', 204))\n\n"
        "def ensure_webui(app):\n"
        "    try:\n"
        "        if 'webui.index' not in app.view_functions:\n"
        "            app.register_blueprint(webui)\n"
        "    except Exception:\n"
        "        pass\n"
    )
else:
    # 2) Si falta ensure_webui() lo agregamos al final
    if "def ensure_webui(" not in s:
        s += (
            "\n\ndef ensure_webui(app):\n"
            "    try:\n"
            "        if 'webui.index' not in app.view_functions:\n"
            "            app.register_blueprint(webui)\n"
            "    except Exception:\n"
            "        pass\n"
        )
p.write_text(s, encoding="utf-8")
print("webui.py OK")
PY

echo "➤ Adjuntar ensure_webui(app) desde backend/__init__.py (sin romper factory)"
python - <<'PY'
from pathlib import Path, re, sys
p = Path("backend/__init__.py")
s = p.read_text(encoding="utf-8")
block = (
    "\n# === attach webui (idempotente) ===\n"
    "try:\n"
    "    from .webui import ensure_webui  # type: ignore\n"
    "    if 'app' in globals():\n"
    "        try:\n"
    "            ensure_webui(app)  # type: ignore\n"
    "        except Exception:\n"
    "            pass\n"
    "except Exception:\n"
    "    pass\n"
)
if "attach webui (idempotente)" not in s:
    # Insertamos cerca del final, pero ANTES de cualquier 'return app' de una posible factory
    # Si no hay 'return app', lo pegamos al final.
    import regex as r
    m = r.search(r"\n\s*return\s+app\b", s)
    if m:
        s = s[:m.start()] + block + s[m.start():]
    else:
        s = s.rstrip() + block + "\n"
    # Validar sintaxis
    try:
        compile(s, str(p), 'exec')
    except SyntaxError as e:
        print("(!) Abort: error de sintaxis al inyectar:", e)
        sys.exit(2)
    p.write_text(s, encoding="utf-8")
    print("__init__.py actualizado")
else:
    print("__init__.py ya tenía el attach (ok)")
PY

echo "➤ Compat wsgi:app -> backend.entry:app (por si Render usa wsgi)"
if [ ! -f wsgi.py ]; then
  cat > wsgi.py <<'PY'
from backend.entry import app  # noqa: F401
PY
  echo "wsgi.py creado"
else
  echo "wsgi.py ya existe (ok)"
fi

echo "➤ Asegurar /api/_routes en el blueprint API"
python - <<'PY'
from pathlib import Path, re
p = Path("backend/routes.py")
s = p.read_text(encoding="utf-8")
if not re.search(r'@api\.route\("/_routes"', s):
    s += """

@api.route("/_routes", methods=["GET"])
def api_routes_dump():
    from flask import current_app, jsonify
    info = []
    for r in current_app.url_map.iter_rules():
        info.append({
            "rule": str(r),
            "methods": sorted(m for m in r.methods if m not in ("HEAD","OPTIONS")),
            "endpoint": r.endpoint,
        })
    return jsonify({"routes": sorted(info, key=lambda x: x["rule"])}), 200
"""
    p.write_text(s, encoding="utf-8")
    print("Añadido /api/_routes en blueprint API")
else:
    print("/api/_routes ya estaba (ok)")
PY

echo "➤ Commit & push"
git add backend/webui.py backend/__init__.py wsgi.py backend/routes.py
git commit -m "fix(web): adjuntar blueprint frontend desde __init__ (idempotente), compat wsgi:app y /api/_routes estable"
git push origin main

echo "➤ Probar en producción (cabeceras)"
BASE="${BASE:-https://paste12-rmsk.onrender.com}"
for p in / /js/app.js /css/styles.css /robots.txt /api/health /api/_routes; do
  echo "--- $p"
  curl -sSI "$BASE$p" | head -n 12 || true
done
echo "Listo."
