#!/usr/bin/env bash
set -Eeuo pipefail

python - <<'PY'
from pathlib import Path
import re

p = Path('backend/routes.py')
s = p.read_text(encoding='utf-8')

changed = False

# 1) Asegurar ENABLE_VIEWS=1 por defecto al importar el módulo
if "os.environ.setdefault(\"ENABLE_VIEWS\",\"1\")" not in s:
    # insertar tras el primer "import os" o, si no existe, crear import os y setdefault
    if re.search(r'^\s*import\s+os\b', s, flags=re.M):
        s = re.sub(r'^\s*import\s+os\b.*',
                   lambda m: m.group(0) + '\nos.environ.setdefault("ENABLE_VIEWS","1")',
                   s, count=1, flags=re.M)
    else:
        # insertar al inicio tras otros imports
        s = re.sub(r'^(from\s+[^\n]+\n|import\s+[^\n]+\n)+',
                   lambda m: m.group(0) + 'import os\nos.environ.setdefault("ENABLE_VIEWS","1")\n',
                   s, count=1, flags=re.S) or ('import os\nos.environ.setdefault("ENABLE_VIEWS","1")\n' + s)
    changed = True

# 2) Normalizar cualquier default "0" -> "1" (solo para ENABLE_VIEWS)
s2 = re.sub(r'os\.getenv\(\s*[\'"]ENABLE_VIEWS[\'"]\s*,\s*[\'"]0[\'"]\s*\)',
            'os.getenv("ENABLE_VIEWS","1")', s)
if s2 != s:
    s = s2
    changed = True

# 3) Reescribir el handler /view con una versión estable
pattern = r'@bp\.post\("/notes/<int:note_id>/view"\)\s+def\s+view_note\([^\)]*\):[\s\S]*?(?=\n@bp\.|\\Z)'
replacement = r'''@bp.post("/notes/<int:note_id>/view")
def view_note(note_id: int):
    from flask import jsonify
    import os
    # Kill-switch (ahora por defecto 1)
    if os.getenv("ENABLE_VIEWS", "1") != "1":
        n = Note.query.get_or_404(note_id)
        return jsonify({"counted": False, "views": int(n.views or 0)})

    n = Note.query.get_or_404(note_id)
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
        # ya vio hoy con este fp
    return jsonify({"counted": counted, "views": int(n.views or 0)})'''

s3 = re.sub(pattern, replacement, s, flags=re.S)
if s3 != s:
    s = s3
    changed = True

if changed:
    p.write_text(s, encoding='utf-8')
    print("✓ routes.py actualizado: ENABLE_VIEWS=1 por defecto + view handler estable")
else:
    print("• routes.py ya estaba correcto (no se hicieron cambios)")
PY

# Validar sintaxis
python -m py_compile backend/routes.py && echo "✓ Sintaxis OK"

# Commit & push
git add backend/routes.py
git commit -m "feat(views): force ENABLE_VIEWS=1 por defecto y handler /view estable" || true
git push -u origin main
