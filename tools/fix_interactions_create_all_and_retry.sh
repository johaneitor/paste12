#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"

echo "[1/3] Parcheando render_entry.py para crear esquema al iniciar…"
python - <<'PY'
import io,re,sys,os
p="render_entry.py"
s=open(p,"r",encoding="utf-8").read()
# Asegurar import de ensure_schema/register_into/register_alias_into
if "from backend.modules.interactions import ensure_schema" not in s:
    s += "\nfrom backend.modules.interactions import ensure_schema, register_into, register_alias_into\n"
elif "register_into" not in s or "register_alias_into" not in s:
    s = s.replace("from backend.modules.interactions import ensure_schema",
                  "from backend.modules.interactions import ensure_schema, register_into, register_alias_into")

# Inyectar bloque de startup que corre dentro de app.app_context()
guard = "##__INTERACTIONS_BOOTSTRAP__"
if guard not in s:
    inject = f"""
{guard}
try:
    from flask import current_app as _cap
    _app = _cap._get_current_object() if _cap else app
except Exception:
    _app = app if 'app' in globals() else None

try:
    if _app is not None:
        with _app.app_context():
            try:
                ensure_schema()
            except Exception:  # no romper boot
                pass
            try:
                register_into(_app)
            except Exception:
                pass
            try:
                register_alias_into(_app)
            except Exception:
                pass
except Exception:
    pass
"""
    s = s.rstrip()+"\n"+inject

open(p,"w",encoding="utf-8").write(s)
print("[OK] render_entry.py listo")
PY

echo "[2/3] Endureciendo backend/modules/interactions.py con auto-create y retry…"
python - <<'PY'
import re,sys,io,os
p="backend/modules/interactions.py"
s=open(p,"r",encoding="utf-8").read()

# Asegurar que exista ensure_schema()
if "def ensure_schema(" not in s:
    s += """

def ensure_schema():
    try:
        db.create_all()
    except Exception:
        pass
"""

# Helper para detectar missing-table y reintentar
if "_MISSING_EVT_ERRS" not in s:
    s += """
_MISSING_EVT_ERRS = ("no such table: interaction_event", "UndefinedTable: relation \\"interaction_event\\"")
def _maybe_bootstrap_schema_and_retry(fn, *args, **kwargs):
    try:
        return fn(*args, **kwargs)
    except Exception as e:
        msg = str(e).lower()
        if any(t in msg for t in _MISSING_EVT_ERRS):
            try:
                ensure_schema()
            except Exception:
                pass
            # retry 1 vez
            return fn(*args, **kwargs)
        raise
"""

# Envolver like/view/stats con el retry
def wrap_handler(code:str,name:str)->str:
    pat = rf"@bp\.post\(\"/notes/<int:note_id>/{name}\"\)[\s\S]*?def {name}_note\(note_id: int\):([\s\S]*?)\n@"
    m = re.search(pat, code)
    if not m:
        # alterno (por si endpoint cargó con alias distinto)
        pat = rf"@bp\.post\(\"/notes/<int:note_id>/{name}\"\)[\s\S]*?def {name}_note\(note_id: int\):([\s\S]*?)\Z"
        m = re.search(pat, code)
    if not m:
        return code
    body = m.group(1)
    new = re.sub(rf"def {name}_note\(note_id: int\):",
                 rf"def {name}_note(note_id: int):\n    def _do(note_id=note_id):", m.group(0), count=1)
    new = new.replace("return jsonify", "        return jsonify")
    new = new.replace("db.session", "        db.session")
    new = new.replace("\n@", "\n    # end _do\n    return _maybe_bootstrap_schema_and_retry(_do)\n\n@")
    return code.replace(m.group(0), new)

# stats es GET
def wrap_stats(code:str)->str:
    pat = r"@bp\.get\(\"/notes/<int:note_id>/stats\"\)[\s\S]*?def stats_note\(note_id: int\):([\s\S]*?)\Z"
    m = re.search(pat, code)
    if not m:
        pat = r"@bp\.get\(\"/notes/<int:note_id>/stats\"\)[\s\S]*?def stats_note\(note_id: int\):([\s\S]*?)\n@"
        m = re.search(pat, code)
    if not m:
        return code
    new = re.sub(r"def stats_note\(note_id: int\):",
                 r"def stats_note(note_id: int):\n    def _do(note_id=note_id):", m.group(0), count=1)
    new = new.replace("return jsonify", "        return jsonify")
    new = new.replace("\n@", "\n    # end _do\n    return _maybe_bootstrap_schema_and_retry(_do)\n\n@")
    return code.replace(m.group(0), new)

s = wrap_handler(s,"like")
s = wrap_handler(s,"view")
s = wrap_stats(s)

# Añadir /api/notes/diag si no existe
if 'endpoint="interactions_diag"' not in s:
    s += """
@bp.get("/notes/diag", endpoint="interactions_diag")
def interactions_diag():
    try:
        from sqlalchemy import inspect as _inspect
        eng = db.get_engine()
        inspector = _inspect(eng)
        tables = inspector.get_table_names()
        has_evt = "interaction_event" in tables
        likes_cnt = views_cnt = None
        if has_evt:
            from sqlalchemy import func as _f
            likes_cnt = db.session.query(_f.count(InteractionEvent.id)).filter_by(type="like").scalar() or 0
            views_cnt = db.session.query(_f.count(InteractionEvent.id)).filter_by(type="view").scalar() or 0
        return jsonify(ok=True, tables=tables, has_interaction_event=has_evt,
                       total_likes=(int(likes_cnt) if likes_cnt is not None else None),
                       total_views=(int(views_cnt) if views_cnt is not None else None)), 200
    except Exception as e:
        return jsonify(ok=False, error="diag_failed", detail=str(e)), 500
"""

open(p,"w",encoding="utf-8").write(s)
print("[OK] interactions.py endurecido")
PY

echo "[3/3] Commit & push"
git add -A
git commit -m "fix(interactions): create_all on startup + auto-heal on missing table (retry) + /api/notes/diag" || true
git push -u --force-with-lease origin "$(git rev-parse --abbrev-ref HEAD)"

echo
echo "Hecho. Tras redeploy, valida con:"
cat <<'CMD'
curl -s https://paste12-rmsk.onrender.com/api/notes/diag | jq .
ID=$(curl -s 'https://paste12-rmsk.onrender.com/api/notes?page=1' | jq -r '.[0].id'); echo "Usando ID=$ID"
curl -i -s -X POST "https://paste12-rmsk.onrender.com/api/ix/notes/$ID/like" | sed -n '1,80p'
curl -i -s -X POST "https://paste12-rmsk.onrender.com/api/ix/notes/$ID/view" | sed -n '1,80p'
curl -i -s     "https://paste12-rmsk.onrender.com/api/ix/notes/$ID/stats"     | sed -n '1,120p'
CMD
