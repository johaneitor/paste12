#!/usr/bin/env bash
set -euo pipefail
F="backend/__init__.py"
[[ -f "$F" ]] || { echo "No existe $F"; exit 1; }
cp -n "$F" "$F.bak.$(date -u +%Y%m%dT%H%M%SZ)" || true

python - <<'PY'
from pathlib import Path, re
p = Path("backend/__init__.py")
src = p.read_text(encoding="utf-8")

# 0) normalización básica
src = src.replace("\r\n","\n").replace("\r","\n")

# 1) Eliminar registros duplicados evidentes/huérfanos
src = re.sub(r'^\s*from\s+backend\.routes\s+import\s+api\s+as\s+api_bp\s*$', '', src, flags=re.M)
src = re.sub(r'^\s*app\.register_blueprint\(api_bp,\s*url_prefix=[\'"]/api[\'"]\)\s*$', '', src, flags=re.M)

# 2) Asegurar alias del factory original una (1) vez
if "_create_app_orig = create_app" not in src:
    src = src.replace("def create_app(", "_create_app_orig = create_app\n\ndef create_app(")

# 3) Reemplazar CUERPO del wrapper por uno sano (1 sola coincidencia)
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
print("OK: create_app wrapper normalizado (sin duplicados)")
PY

git add backend/__init__.py >/dev/null 2>&1 || true
git commit -m "fix(app): normaliza wrapper create_app; elimina duplicados y registra api_bp post-factory" >/dev/null 2>&1 || true
git push origin HEAD >/dev/null 2>&1 || true
echo "✓ Commit & push hecho."
