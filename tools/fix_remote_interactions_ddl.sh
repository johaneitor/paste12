#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"

note(){ printf "    - %s\n" "$*"; }

# --- 1) Parchar render_entry.py para asegurar import + ensure_schema() en app_context ---
if [ -f render_entry.py ]; then
  cp -f render_entry.py "render_entry.py.bak.$(date +%s)"
  python - <<'PY'
import re, sys, os
p="render_entry.py"
s=open(p,"r",encoding="utf-8").read()

# inyecta import y boot si no están
if "from backend.modules.interactions import ensure_schema" not in s:
    s = s.rstrip()+"\nfrom backend.modules.interactions import ensure_schema\n"

boot_re = re.compile(r"with app\.app_context\(\):\s*db\.create_all\(\)", re.M)
if not boot_re.search(s):
    # Inserta un bloque robusto que crea tablas del core + interactions
    s += """

# --- boot: ensure DB schema for core + interactions (idempotent) ---
try:
    from backend import db as _db
    with app.app_context():
        try:
            _db.create_all()
        except Exception:
            pass
        try:
            ensure_schema()
        except Exception:
            pass
except Exception:
    pass
"""

open(p,"w",encoding="utf-8").write(s)
print("[OK] render_entry.py: ensure_schema() + create_all() in app_context")
PY
else
  echo "[i] No existe render_entry.py (ok si usas solo wsgiapp)."
fi

# --- 2) Asegurar diagnósticos en interactions (tabla, counts, errores) ---
mkdir -p backend/modules
if [ -f backend/modules/interactions.py ]; then
  cp -f backend/modules/interactions.py "backend/modules/interactions.py.bak.$(date +%s)"
  python - <<'PY'
import re
p="backend/modules/interactions.py"
s=open(p,"r",encoding="utf-8").read()

# Añadir un endpoint diag si no existe
if 'endpoint="interactions_diag"' not in s:
    s += """

# === Diag: existencia de tabla y counts básicos ===
@bp.get("/notes/diag", endpoint="interactions_diag")
def interactions_diag():
    try:
        eng = db.get_engine()
        insp = getattr(eng, "inspect", None)
        # SQLAlchemy 2.x pattern
        from sqlalchemy import inspect as _inspect
        inspector = _inspect(eng)
        tables = inspector.get_table_names()
        has_evt = "interaction_event" in tables
        likes_cnt = views_cnt = None
        if has_evt:
            likes_cnt = db.session.query(func.count(InteractionEvent.id)).filter_by(type="like").scalar() or 0
            views_cnt = db.session.query(func.count(InteractionEvent.id)).filter_by(type="view").scalar() or 0
        return jsonify(ok=True, tables=tables, has_interaction_event=has_evt,
                       total_likes=int(likes_cnt) if likes_cnt is not None else None,
                       total_views=int(views_cnt) if views_cnt is not None else None), 200
    except Exception as e:
        return jsonify(ok=False, error="diag_failed", detail=str(e)), 500
"""
    open(p,"w",encoding="utf-8").write(s)
    print("[OK] interactions.py: añadido /api/notes/diag")
else:
    print("[=] interactions.py ya tiene diag")
PY
else
  echo "[!] No existe backend/modules/interactions.py; abortando para evitar inconsistencias."
  exit 1
fi

# --- 3) Commit & push ---
git add -A
git commit -m "fix(interactions): ensure schema on startup + add /api/notes/diag" || true
git push -u --force-with-lease origin "$(git rev-parse --abbrev-ref HEAD)"

cat <<'NEXT'

[✓] Parche enviado.

Ahora en Render:
1) Asegúrate que DATABASE_URL esté seteado (si es postgres://, el código lo normaliza a postgresql://).
2) Haz un redeploy (ideal "Clear build cache" para reinstalar dependencias si cambiaste requirements).
3) Prueba:

    bash tools/remote_probe_wsgiapp.sh
    # y específicamente:
    curl -s https://paste12-rmsk.onrender.com/api/notes/diag | jq .

Si /api/notes/diag dice "has_interaction_event: true", repetí:
  curl -i -s -X POST https://paste12-rmsk.onrender.com/api/ix/notes/1/like
  curl -i -s -X POST https://paste12-rmsk.onrender.com/api/ix/notes/1/view
  curl -i -s     https://paste12-rmsk.onrender.com/api/ix/notes/1/stats

Deberían responder 200 JSON (no 500).
NEXT
