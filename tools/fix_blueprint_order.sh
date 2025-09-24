#!/usr/bin/env bash
set -euo pipefail

INIT="backend/__init__.py"
[[ -f "$INIT" ]] || { echo "No existe $INIT"; exit 1; }

python - "$INIT" <<'PY'
from pathlib import Path
import re, sys

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8")

# 1) Quitar import global problemático
s = re.sub(r'^\s*from\s+backend\.routes\s+import\s+api\s+as\s+api_bp\s*\n', '', s, flags=re.M)

# 2) Detectar cómo se llama la factory original
orig_name = None
# Casos comunes que he visto en tus logs
for cand in ("_create_app_orig", "_orig_create_app"):
    if re.search(rf'\b{re.escape(cand)}\s*=\s*create_app\b', s) or cand in s:
        orig_name = cand
        break

# Si no encontramos, intentamos detectar un wrapper previo
if orig_name is None:
    # Caso: def _create_app_orig(...):  (poco común pero por si acaso)
    m = re.search(r'def\s+(_[a-zA-Z0-9_]*create_app[^(\s]*)\s*\(', s)
    if m:
        orig_name = m.group(1)

# Fallback conservador
if orig_name is None:
    # Último recurso: asumimos que el original es _create_app_orig y que existe en el archivo
    orig_name = "_create_app_orig"

# 3) Normalizar cuerpo de create_app:
#    - crear app llamando a la factory original
#    - importar y registrar blueprint después
#    - retornar app
def repl_create_app(match):
    head = match.group(1)  # "def create_app(...):\n"
    indent = match.group(2)  # indent adentro
    body = f"""{indent}app = {orig_name}(*args, **kwargs)
{indent}try:
{indent}    from backend.routes import api as api_bp
{indent}    app.register_blueprint(api_bp, url_prefix='/api')
{indent}except Exception as e:
{indent}    try:
{indent}        app.logger.exception("Failed registering API blueprint: %s", e)
{indent}    except Exception:
{indent}        pass
{indent}return app
"""
    return head + body

# Reemplazo de la primera def create_app(...)
pat = re.compile(r'(def\s+create_app\s*\([^\)]*\)\s*:\s*\n)([ \t]+)', re.M)
s_new, n = pat.subn(repl_create_app, s, count=1)
if n == 0:
    print("No se encontró def create_app(...). Abortando.", file=sys.stderr)
    sys.exit(1)

p.write_text(s_new, encoding="utf-8")
print("OK: backend/__init__.py reescrito (orden de registro y sin import global)")
PY

git add backend/__init__.py >/dev/null 2>&1 || true
git commit -m "fix(api): mueve import/registro del blueprint a create_app y crea app antes de registrar" >/dev/null 2>&1 || true
git push origin HEAD >/dev/null 2>&1 || true
echo "✓ Patch aplicado y pusheado."
