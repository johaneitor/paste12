#!/usr/bin/env bash
set -Eeuo pipefail

echo "➤ Asegurar ensure_webui() en backend/webui.py"
python - <<'PY'
from pathlib import Path
p = Path("backend/webui.py")
s = p.read_text(encoding="utf-8")
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
    if "def ensure_webui(" not in s:
        s += (
            "\n\ndef ensure_webui(app):\n"
            "    try:\n"
            "        if 'webui.index' not in app.view_functions:\n"
            "            app.register_blueprint(webui)\n"
            "    except Exception:\n"
            "        pass\n"
        )
Path("backend/webui.py").write_text(s, encoding="utf-8")
print("webui.py OK")
PY

echo "➤ Adjuntar ensure_webui(app) en backend/__init__.py (sin regex, seguro)"
python - <<'PY'
from pathlib import Path, sys
p = Path("backend/__init__.py")
s = p.read_text(encoding="utf-8")

attach = """
# === attach webui (idempotente, no-regex) ===
try:
    from .webui import ensure_webui  # type: ignore
    # Wrap factory si existe
    if 'create_app' in globals() and callable(create_app):
        _orig_create_app = create_app  # type: ignore
        def create_app(*args, **kwargs):  # type: ignore[no-redef]
            app = _orig_create_app(*args, **kwargs)
            try:
                ensure_webui(app)
            except Exception:
                pass
            return app
    # Adjuntar a app global si existe
    if 'app' in globals():
        try:
            ensure_webui(app)  # type: ignore
        except Exception:
            pass
except Exception:
    pass
""".strip("\n") + "\n"

if "attach webui (idempotente, no-regex)" not in s:
    s2 = s.rstrip() + "\n\n" + attach
    try:
        compile(s2, str(p), "exec")
    except SyntaxError as e:
        print("(!) Abort: error de sintaxis al inyectar:", e)
        sys.exit(2)
    p.write_text(s2, encoding="utf-8")
    print("__init__.py actualizado")
else:
    print("__init__.py ya tenía el attach (ok)")
PY

echo "➤ Asegurar wsgi.py (compat wsgi:app)"
[ -f wsgi.py ] || echo "from backend.entry import app  # noqa: F401" > wsgi.py

echo "➤ Commit & push"
git add backend/webui.py backend/__init__.py wsgi.py
git commit -m "fix(web): adjuntar blueprint frontend (global y factory) sin dependencias externas; compat wsgi:app"
git push origin main

echo "Listo. Probá luego en producción:"
echo 'BASE="https://paste12-rmsk.onrender.com"; for p in / /js/app.js /css/styles.css /robots.txt /api/health /api/_routes; do echo --- $p; curl -sSI "$BASE$p" | head -n 12; done'
