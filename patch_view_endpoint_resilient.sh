#!/usr/bin/env bash
set -Eeuo pipefail
file="backend/routes.py"
cp -a "$file" "$file.bak.$(date +%s)"

python - <<'PY'
import re, pathlib
p = pathlib.Path("backend/routes.py")
code = p.read_text(encoding="utf-8")

# Asegurar import IntegrityError
if "from sqlalchemy.exc import IntegrityError" not in code:
    code = code.replace(
        "from flask import Blueprint, current_app, jsonify, request",
        "from flask import Blueprint, current_app, jsonify, request\nfrom sqlalchemy.exc import IntegrityError",
        1
    )

# Reemplazar por una versión a prueba de balas del handler /view
pattern = r'@bp\.post\("/notes/<int:note_id>/view"\)[\s\S]*?def\s+view_note\([^\)]*\):[\s\S]*?(?=\n@bp\.|\Z)'
replacement = r'''@bp.post("/notes/<int:note_id>/view")
def view_note(note_id: int):
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
        return jsonify({"views": int(n.views or 0), "counted": True, "ok": True}), 200
    except IntegrityError:
        # vista duplicada (única por día): no contamos
        db.session.rollback()
        try:
            db.session.refresh(n)
        except Exception:
            pass
        return jsonify({"views": int(n.views or 0), "counted": False, "ok": True}), 200
    except Exception as e:
        # no romper el feed por errores raros de DB
        db.session.rollback()
        try:
            current_app.logger.error(f"/view failed for note {note_id}: {e}")
        except Exception:
            pass
        try:
            db.session.refresh(n)
        except Exception:
            pass
        return jsonify({"views": int(n.views or 0), "counted": False, "ok": False, "error": str(e)[:120]}), 200
'''
new, n = re.subn(pattern, replacement, code, flags=re.S)
if n == 0:
    raise SystemExit("No se encontró el bloque /view para parchear.")
p.write_text(new, encoding="utf-8")
print("✓ /view parcheado a prueba de balas")
PY

python -m py_compile backend/routes.py && echo "✅ Sintaxis OK" || { echo "❌ Error de sintaxis"; exit 1; }

echo
echo "Ahora reinicia local o haz push:"
echo "  git add backend/routes.py && git commit -m 'hotfix(view): /view resiliente (sin 500)' || true"
echo "  git push -u origin main"
echo "Y prueba:"
echo "  curl -sSf https://paste12-rmsk.onrender.com/api/health"
echo "  curl -sSf 'https://paste12-rmsk.onrender.com/api/notes?page=1' | head -c 300; echo"
