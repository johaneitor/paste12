#!/usr/bin/env bash
set -euo pipefail
F="render_entry.py"
[ -f "$F" ] || { echo "[!] No existe $F"; exit 1; }
cp -f "$F" "$F.bak.$(date +%s)"

python - <<'PY'
import re, io, sys
p="render_entry.py"
s=open(p,"r",encoding="utf-8").read()

# El bloque bueno que vamos a inyectar (indentación consistente)
good = r'''
# --- interactions bootstrap (clean) start ---
try:
    # Módulo encapsulado (events + counters, no-unlike)
    from backend.modules.interactions import (
        bp as interactions_bp,
        alias_bp as interactions_alias_bp,
        ensure_schema as _ix_ensure_schema,
    )
except Exception:
    interactions_bp = None
    interactions_alias_bp = None
    def _ix_ensure_schema():
        return None

def _ix_bootstrap(_app):
    try:
        if _ix_ensure_schema:
            with _app.app_context():
                _ix_ensure_schema()
        if interactions_bp is not None:
            try:
                _app.register_blueprint(interactions_bp, url_prefix="/api")
            except Exception:
                pass
        if interactions_alias_bp is not None:
            try:
                _app.register_blueprint(interactions_alias_bp, url_prefix="/api")
            except Exception:
                pass
    except Exception:
        # no romper arranque
        pass

try:
    _ix_bootstrap(app)
except Exception:
    pass

# Diag + reparación mínima para el esquema de interacciones
from flask import Blueprint as _BP_, jsonify as _jsonify_
_ixdiag = _BP_("ixdiag_render_entry", __name__)

@_ixdiag.post("/notes/repair-interactions")
def repair_interactions():
    try:
        if _ix_ensure_schema:
            with app.app_context():
                _ix_ensure_schema()
        return _jsonify_(ok=True, repaired=True), 200
    except Exception as e:
        return _jsonify_(ok=False, error="repair_failed", detail=str(e)), 500

@_ixdiag.get("/notes/diag")
def notes_diag():
    try:
        from sqlalchemy import inspect as _inspect, func as _func
        from backend.modules.interactions import InteractionEvent
        eng = db.get_engine()
        inspector = _inspect(eng)
        tables = inspector.get_table_names()
        has_evt = "interaction_event" in tables
        out = {"tables": tables, "has_interaction_event": has_evt}
        if has_evt:
            likes_cnt = db.session.query(_func.count(InteractionEvent.id)).filter_by(type="like").scalar() or 0
            views_cnt = db.session.query(_func.count(InteractionEvent.id)).filter_by(type="view").scalar() or 0
            out["total_likes"] = int(likes_cnt)
            out["total_views"] = int(views_cnt)
        return _jsonify_(ok=True, **out), 200
    except Exception as e:
        return _jsonify_(ok=False, error="diag_failed", detail=str(e)), 500

try:
    app.register_blueprint(_ixdiag, url_prefix="/api")
except Exception:
    pass
# --- interactions bootstrap (clean) end ---
'''.lstrip("\n")

# 1) Elimina cualquier bloque previo roto relacionado (entre los marcadores si existen)
pat = re.compile(
    r"# --- interactions bootstrap .*?start ---[\\s\\S]*?# --- interactions bootstrap .*?end ---",
    re.M
)
if pat.search(s):
    s = pat.sub(good, s)
else:
    # Si no hay marcadores, lo agregamos al final del archivo
    s = s.rstrip() + "\n\n" + good

open(p,"w",encoding="utf-8").write(s)
print("[OK] render_entry.py actualizado")
PY

echo "[+] Commit & push"
git add render_entry.py
git commit -m "fix(render_entry): replace interactions bootstrap with clean block (indent OK) + diag/repair" || true
git push -u --force-with-lease origin "$(git rev-parse --abbrev-ref HEAD)"

echo "[i] Luego valida con:"
cat <<'CMD'
APP="https://paste12-rmsk.onrender.com"
curl -s "$APP/api/diag/import" | jq .
curl -s "$APP/api/debug-urlmap" | jq '.rules | map(select(.rule|test("^/api/(notes|ix)/")))' 
curl -s "$APP/api/notes/diag" | jq .
curl -si -X POST "$APP/api/notes/repair-interactions" | sed -n '1,120p'
ID=$(curl -s "$APP/api/notes?page=1" | jq -r '.[0].id'); echo "ID=$ID"
curl -si -X POST "$APP/api/ix/notes/$ID/like"  | sed -n '1,120p'
curl -si -X POST "$APP/api/ix/notes/$ID/view"  | sed -n '1,120p'
curl -si      "$APP/api/ix/notes/$ID/stats"   | sed -n '1,160p'
CMD
