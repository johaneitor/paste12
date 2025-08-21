#!/usr/bin/env bash
set -Eeuo pipefail
echo "🔧 Perf safe mode: desactivar views masivas + cache corto del feed + PAGE_SIZE prudente"

# 1) Parchear backend/routes.py: cache en /notes y "no-op" de /view si ENABLE_VIEWS=0
cp -n backend/routes.py backend/routes.py.bak.$(date +%s) || true
python - <<'PY'
import re, pathlib, os
p = pathlib.Path("backend/routes.py")
code = p.read_text(encoding="utf-8")

# Asegurar import os
if "import os" not in code.splitlines()[0:50]:
    code = code.replace("from __future__ import annotations", "from __future__ import annotations\nimport os", 1)

# clamp PAGE_SIZE a 15 por defecto (y hasta 50)
code = re.sub(
    r"def _per_page\(\):.*?return [^\n]+",
    "def _per_page():\n    try:\n        v = int(os.getenv('PAGE_SIZE','15'))\n    except Exception:\n        v = 15\n    return max(10, min(v, 50))",
    code,
    flags=re.S
)

# Añadir Cache-Control en /api/notes (respuesta)
code = re.sub(
    r"return jsonify\(\{([\s\S]*?)\}\)",
    "from flask import make_response\n    _resp = jsonify({\\1})\n    try:\n        _resp.headers['Cache-Control'] = 'public, max-age=5'\n    except Exception:\n        pass\n    return _resp",
    code, count=1
)

# Hacer /view super liviano si ENABLE_VIEWS=0 (sin escribir)
code = re.sub(
    r"@bp\.post\(\"/notes/<int:note_id>/view\"\)\s*def view_note.*?\n(.*?)\n\s*return jsonify\(\{\"views\":.*?\}\)",
    r"""@bp.post("/notes/<int:note_id>/view")
def view_note(note_id: int):
    n = Note.query.get_or_404(note_id)
    # Kill-switch de vistas para performance
    if os.getenv("ENABLE_VIEWS","1") == "0":
        return jsonify({"views": int(n.views or 0), "counted": False})
    fp = _fp()
    today = _now().date()
    counted = False
    try:
        db.session.add(ViewLog(note_id=note_id, fingerprint=fp, view_date=today))
        db.session.flush()
        n.views = int(n.views or 0) + 1
        db.session.commit()
        counted = True
    except IntegrityError:
        db.session.rollback()
    return jsonify({"views": int(n.views or 0), "counted": counted})""",
    code,
    flags=re.S
)

p.write_text(code, encoding="utf-8")
print("✓ routes.py parcheado (PAGE_SIZE=15 cap 50, cache corto, kill-switch de views)")
PY

# 2) Sugerir Procfile de un solo worker si sigues en SQLite
if grep -q "Procfile" Procfile 2>/dev/null; then
  cp -n Procfile Procfile.bak.$(date +%s) || true
  sed -i "s/gunicorn .*$/gunicorn \"backend:create_app()\" -w 1 -k gthread --threads 16 -b 0.0.0.0:\$PORT --timeout 60/" Procfile || true
  echo "✓ Procfile ajustado a 1 worker (SQLite-friendly)"
fi

# 3) Validación sintaxis
python -m py_compile backend/routes.py

echo
echo "✅ Hecho. Ahora:"
echo "   - En Render → Environment, pon: ENABLE_VIEWS=0, PAGE_SIZE=15"
echo "   - (Opcional) Si sigues en SQLite, deja 1 worker (Procfile ya ajustado)"
echo "   - git add backend/routes.py Procfile && git commit -m 'perf(safe): cache corto, kill-switch de views y PAGE_SIZE=15' || true"
echo "   - git push -u origin main  → Redeploy"
echo
echo "Verificación rápida:"
echo "   curl -sSf https://TU_HOST/api/health"
echo "   curl -sSf 'https://TU_HOST/api/notes?page=1' | head -c 400; echo"
