#!/usr/bin/env bash
set -euo pipefail
F="backend/__init__.py"
[[ -f "$F" ]] || { echo "No existe $F"; exit 1; }
cp -n "$F" "$F.bak.$(date -u +%Y%m%dT%H%M%SZ)" || true

python - <<'PY'
from pathlib import Path, re
p = Path("backend/__init__.py")
src = p.read_text(encoding="utf-8")

# quitar duplicados obvios de register_blueprint antes de crear app
src = src.replace("app.register_blueprint(api_bp, url_prefix='/api')\n    app = _create_app_orig", "app = _create_app_orig")
src = src.replace("from backend.routes import api as api_bp\n", "")

# asegurar que tenemos un alias del factory original
if "_create_app_orig = create_app" not in src:
    src = src.replace("def create_app(", "_create_app_orig = create_app\n\ndef create_app(")

# reescribir cuerpo del wrapper de forma segura
import re
src = re.sub(
    r"def create_app\([^\)]*\):[\s\S]*?return app",
    '''def create_app(*args, **kwargs):
    app = _create_app_orig(*args, **kwargs)
    try:
        from backend.routes import api as api_bp
        app.register_blueprint(api_bp, url_prefix='/api')
    except Exception as e:
        try:
            app.logger.exception("Failed registering API blueprint: %s", e)
        except Exception:
            pass
    return app''',
    src,
    count=1
)

p.write_text(src, encoding="utf-8")
print("OK: create_app wrapper saneado")
PY

git add backend/__init__.py >/dev/null 2>&1 || true
git commit -m "fix(app): wrapper create_app limpio; registra api_bp post-factory" >/dev/null 2>&1 || true
git push origin HEAD >/dev/null 2>&1 || true
echo "✓ Commit & push hecho."
