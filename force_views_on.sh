#!/usr/bin/env bash
set -Eeuo pipefail

python - <<'PY'
from pathlib import Path, re
p = Path('backend/routes.py')
s = p.read_text(encoding='utf-8')

# Reemplaza TODO el handler de /view por uno simple que cuenta 1 vez por (note_id,fingerprint,día)
pattern = r'@bp\.post\("/notes/<int:note_id>/view"\)\s+def\s+view_note\([^\)]*\):[\s\S]*?(?=\n@bp\.|\Z)'
replacement = r'''@bp.post("/notes/<int:note_id>/view")
def view_note(note_id: int):
    from flask import jsonify
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
    except IntegrityError as e:
        db.session.rollback()
        # si ya había vista previa para (note_id, fp, day) no cuenta
    return jsonify({"counted": counted, "views": int(n.views or 0)})'''

new = re.sub(pattern, replacement, s, flags=re.S)
if new != s:
    p.write_text(new, encoding='utf-8')
    print("✓ /view forzado ON (sin kill-switch)")
else:
    print("• No se encontró el handler a reemplazar (o ya estaba OK)")
PY

python -m py_compile backend/routes.py && echo "✓ Sintaxis OK"

git add backend/routes.py
git commit -m "feat(views): forzar /view siempre activo (1 vista/día por note_id+fingerprint)" || true
git push -u origin main
