#!/usr/bin/env bash
set -euo pipefail

FILE="backend/__init__.py"

[[ -f "$FILE" ]] || { echo "No existe $FILE"; exit 1; }

python - <<'PY'
from pathlib import Path
import re
p=Path("backend/__init__.py")
src=p.read_text(encoding="utf-8").replace("\r\n","\n").replace("\r","\n").replace("\t","    ")

# 1) Eliminar cualquier línea suelta que registre blueprints fuera de una función
src = re.sub(r'^\s*app\.register_blueprint\(.*$', '', src, flags=re.M)

# 2) Asegurar que NO haya “create_app wrapper” roto: añadimos un bloque canónico al final,
#    envolviendo la create_app ya existente (sea la que sea) una única vez.
guard = "# === CANONICAL_CREATE_APP_WRAPPER ==="
if guard not in src:
    block = f"""
{guard}
try:
    _orig_create_app
except NameError:
    _orig_create_app = create_app

def create_app(*args, **kwargs):
    app = _orig_create_app(*args, **kwargs)
    # Registrar API
    try:
        from backend.routes import api as api_bp
        # el blueprint en routes NO tiene prefix; lo ponemos aquí
        app.register_blueprint(api_bp, url_prefix='/api')
    except Exception as e:
        try:
            app.logger.exception("Failed registering API blueprint: %s", e)
        except Exception:
            pass
    # Registrar webui (no crítico)
    try:
        from .webui import webui
        app.register_blueprint(webui)
    except Exception:
        pass
    return app
"""
    src = src.rstrip()+"\n"+block+"\n"

p.write_text(src, encoding="utf-8")
print("OK: backend/__init__.py normalizado")
PY

git add backend/__init__.py >/dev/null 2>&1 || true
git commit -m "fix(factory): wrapper canónico de create_app; evita register_blueprint fuera de función" >/dev/null 2>&1 || true
git push origin HEAD >/dev/null 2>&1 || true
echo "✓ Commit & push enviados."
