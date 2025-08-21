#!/usr/bin/env bash
set -Eeuo pipefail
python - <<'PY'
from pathlib import Path
import re
p = Path('backend/routes.py')
s = p.read_text(encoding='utf-8')

if 'def diag_views()' not in s:
    s += r'''

@bp.get("/admin/diag_views")
def diag_views():
    # requiere token admin por header
    if request.headers.get("X-Admin-Token") != (os.getenv("ADMIN_TOKEN","changeme")):
        return jsonify({"ok": False, "error": "unauthorized"}), 401
    try:
        note_id = int(request.args.get("note_id","0"))
    except Exception:
        return jsonify({"ok": False, "error": "note_id required"}), 400
    today = _now().date()
    rows = db.session.execute(
        db.text("SELECT note_id,fingerprint,view_date FROM view_log WHERE note_id=:nid AND view_date=:vd ORDER BY fingerprint LIMIT 50"),
        {"nid": note_id, "vd": today}
    ).mappings().all()
    return jsonify({"ok": True, "today": str(today), "count": len(rows), "rows": list(rows)}), 200
'''
    p.write_text(s, encoding='utf-8')
    print("✓ admin /admin/diag_views agregado")
else:
    print("• admin /admin/diag_views ya existe")
PY

python -m py_compile backend/routes.py && echo "✓ Sintaxis OK"
git add backend/routes.py
git commit -m "chore(admin): diag_views para inspeccionar view_log por note y día" || true
git push -u origin main
