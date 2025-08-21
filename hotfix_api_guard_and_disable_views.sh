#!/usr/bin/env bash
set -Eeuo pipefail
f="backend/routes.py"

python - <<'PY'
import io, re, sys, pathlib
p = pathlib.Path("backend/routes.py")
code = p.read_text(encoding="utf-8")

# 1) Asegurar import os
if "import os" not in code:
    code = code.replace("from datetime import", "import os\nfrom datetime import")

# 2) Asegurar definición del blueprint 'bp' con url_prefix (idempotente)
code = re.sub(r'bp\s*=\s*Blueprint\(\s*"api"[^)]*\)',
              'bp = Blueprint("api", __name__)', code, count=1)

# 3) Agregar un error handler JSON si no existe
if "def _api_error(" not in code:
    inject = '''
@bp.errorhandler(Exception)
def _api_error(e):
    try:
        current_app.logger.exception("API error: %s", e)
    except Exception:
        pass
    # Siempre JSON, para poder ver el error en curl
    return jsonify({"ok": False, "error": str(e)}), 500
'''
    # lo ponemos después de la definición del bp
    code = re.sub(r'(bp\s*=\s*Blueprint\([^\n]+\)\s*)', r'\1' + inject + '\n', code, count=1)

# 4) Kill-switch de views: early-return si ENABLE_VIEWS=0
code = re.sub(
    r'(\@bp\.post\("/notes/<int:note_id>/view"\)\s*def\s+view_note\([^\)]*\):\s*)',
    r'''\1
    import os as _os
    if _os.getenv("ENABLE_VIEWS","1") != "1":
        # No contar vistas en modo seguro (evita locks de SQLite bajo carga)
        n = Note.query.get_or_404(note_id)
        return jsonify({"views": int(n.views or 0), "counted": False})
''',
    code, count=1, flags=re.S
)

# 5) PAGE_SIZE por defecto a 15 si en tu helper existe
code = re.sub(r'os\.getenv\("PAGE_SIZE",\s*"[0-9]+"\)', 'os.getenv("PAGE_SIZE","15")', code)

p.write_text(code, encoding="utf-8")
print("✓ routes.py parcheado (JSON errors + kill-switch views + PAGE_SIZE=15)")

PY

# Validar sintaxis rápido
python -m py_compile backend/routes.py && echo "✓ Sintaxis OK" || { echo "❌ Error de sintaxis"; exit 1; }

cat <<'NEXT'
----------------------------------------------------------------
Ahora:

1) Subí y despliega:
   git add backend/routes.py
   git commit -m "hotfix(api): handler JSON de errores + kill-switch de vistas + PAGE_SIZE=15" || true
   git push -u origin main

2) En Render → Dashboard → Service → Environment:
   - ENABLE_VIEWS=0
   - PAGE_SIZE=15
   (Guardar y Redeploy)

3) Verifica:
   curl -sS https://paste12-rmsk.onrender.com/api/health
   curl -iS 'https://paste12-rmsk.onrender.com/api/notes?page=1' | sed -n '1,20p'
   curl -sS  'https://paste12-rmsk.onrender.com/api/notes?page=1' | head -c 400; echo

Si /api/notes sigue en 500, el body ahora tendrá {"ok":false,"error":"..."} con el error real.
----------------------------------------------------------------
NEXT
