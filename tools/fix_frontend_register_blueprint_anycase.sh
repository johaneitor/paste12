#!/usr/bin/env bash
set -Eeuo pipefail

INIT="backend/__init__.py"
WEBUI="backend/webui.py"

echo "➤ Backups"
cp -f "$INIT" "$INIT.bak.$(date +%s)" 2>/dev/null || true

python - <<'PY'
from pathlib import Path, re

# 0) Asegurar blueprint webui que sirve /, /js/* y favicon desde <repo>/frontend
webui = Path("backend/webui.py")
if not webui.exists():
    webui.write_text(
        "from flask import Blueprint, send_from_directory\n"
        "from pathlib import Path\n"
        "FRONT_DIR = (Path(__file__).resolve().parent.parent / 'frontend').resolve()\n"
        "webui = Blueprint('webui', __name__)\n\n"
        "@webui.route('/', methods=['GET'])\n"
        "def index():\n"
        "    return send_from_directory(FRONT_DIR, 'index.html')\n\n"
        "@webui.route('/js/<path:fname>', methods=['GET'])\n"
        "def js(fname):\n"
        "    return send_from_directory(FRONT_DIR / 'js', fname)\n\n"
        "@webui.route('/favicon.ico', methods=['GET'])\n"
        "def favicon():\n"
        "    p = FRONT_DIR / 'favicon.ico'\n"
        "    if p.exists():\n"
        "        return send_from_directory(FRONT_DIR, 'favicon.ico')\n"
        "    return ('', 204)\n",
        encoding="utf-8",
    )
    print("webui.py: creado")
else:
    print("webui.py: ok")

p = Path("backend/__init__.py")
s = p.read_text(encoding="utf-8")

# Limpia posibles restos anteriores de rutas estáticas incrustadas
s = re.sub(r'\n# === Static frontend routes.*?^except\s+Exception.*?pass\s*$', '\n', s, flags=re.S|re.M)

# Si ya está registrado, no duplicar
if "register_blueprint(webui)" in s:
    print("__init__.py: ya registraba webui (ok)")
else:
    # 1) Caso con create_app(...)
    m = re.search(r'^\s*def\s+create_app\s*\([^)]*\)\s*:\s*', s, re.M)
    if m:
        # Encuentra el cuerpo de la función hasta el próximo 'def' o EOF
        start_fn = m.end()
        nxt = re.search(r'^\s*def\s+\w+\s*\(', s[start_fn:], re.M)
        end_fn = start_fn + (nxt.start() if nxt else len(s))
        body = s[start_fn:end_fn]

        # indent de la función (espacios antes de 'def')
        indent_match = re.match(r'^(\s*)def\s+create_app', s[m.start():], re.M)
        base_indent = indent_match.group(1) if indent_match else ""
        # indent del contenido
        inner_indent = base_indent + "    "

        if "register_blueprint(webui)" not in body:
            inject = (
                f"\n{inner_indent}try:\n"
                f"{inner_indent}    from .webui import webui\n"
                f"{inner_indent}    app.register_blueprint(webui)\n"
                f"{inner_indent}except Exception:\n"
                f"{inner_indent}    pass\n"
            )
            # Inserta antes de 'return app'
            body_new = re.sub(r'^\s*return\s+app\b', inject + r"\g<0>", body, count=1, flags=re.M)
            if body_new == body:
                # Si no hay 'return app', añade al final del cuerpo
                body_new = body + inject
            s = s[:start_fn] + body_new + s[end_fn:]
            print("__init__.py: blueprint registrado DENTRO de create_app")
        else:
            print("__init__.py: create_app ya tenía blueprint (ok)")
    else:
        # 2) Caso sin create_app: app global (app = Flask(...))
        # Intenta insertar justo después de la línea que crea 'app'
        app_line = re.search(r'^\s*app\s*=\s*Flask\([^)]*\)\s*$', s, re.M)
        reg_code = (
            "\n# Registrar blueprint del frontend\n"
            "try:\n"
            "    from .webui import webui\n"
            "    app.register_blueprint(webui)\n"
            "except Exception:\n"
            "    pass\n"
        )
        if app_line:
            pos = app_line.end()
            s = s[:pos] + reg_code + s[pos:]
            print("__init__.py: blueprint registrado tras 'app = Flask(...)'")
        else:
            # Fallback: agregar al final del archivo (si la app existe a nivel módulo, esto funcionará)
            s = s.rstrip() + "\n" + reg_code
            print("__init__.py: blueprint registrado al final del módulo (fallback)")

p.write_text(s, encoding="utf-8")
PY

echo "➤ Commit & Push"
git add -f backend/__init__.py backend/webui.py || true
git commit -m "fix(web): registrar blueprint webui en backend/__init__.py (factory y global app soportados)" || true
git push origin main

echo "➤ Tips Render"
echo "- Asegura que el Start command apunte al módulo 'backend:app' (o 'backend:create_app()' si usas factory)."
echo "- Con esto, / y /js/app.js deberían dar 200 en Render."
