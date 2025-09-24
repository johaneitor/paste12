#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"

FILE="render_entry.py"
[ -f "$FILE" ] || { echo "[!] No existe ${FILE}. Abortando."; exit 1; }

echo "[+] Backup de ${FILE}"
cp -f "$FILE" "$FILE.bak.$(date +%s)"

python - <<'PY'
import re, io, sys

p="render_entry.py"
s=open(p,"r",encoding="utf-8").read()

# 1) Eliminar bloques viejos que pudieran romper indentación
markers = [
    r"# >>> interactions_module_autoreg.*?# <<< interactions_module_autoreg",
    r"# --- interactions alias only \(render_entry\) start ---.*?# --- interactions alias only \(render_entry\) end ---",
    r"# --- interactions bootstrap \(clean\) start ---.*?# --- interactions bootstrap \(clean\) end ---",
]
for m in markers:
    s = re.sub(m, "", s, flags=re.S|re.M)

# 2) Bloque limpio (sin indent raro) para bootstrap + alias + diag/repair
block = r'''
# --- interactions bootstrap (clean) start ---
try:
    # Módulo encapsulado (events + counters, no-unlike)
    from backend.modules.interactions import (
        bp as interactions_bp,
        alias_bp as interactions_alias_bp,
        ensure_schema as _ix_ensure_schema,
    )
except Exception as _e_ix_import:
    interactions_bp = None
    interactions_alias_bp = None
    def _ix_ensure_schema():
        return None

def _ix_try_register(_app):
    try:
        # Crear tablas necesarias
        if _ix_ensure_schema:
            with _app.app_context():
                _ix_ensure_schema()
        # Registrar blueprints (idempotente)
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
        # No romper el arranque
        pass

try:
    _ix_try_register(app)
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
        eng = db.get_engine()
        inspector = _inspect(eng)
        tables = inspector.get_table_names()
        has_evt = "interaction_event" in tables
        out = {"tables": tables, "has_interaction_event": has_evt}
        if has_evt:
            from backend.modules.interactions import InteractionEvent
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
'''

# 3) Insertar el bloque al FINAL del archivo
s = s.rstrip() + "\n" + block + "\n"
open(p,"w",encoding="utf-8").write(s)
print("[OK] render_entry.py saneado e instrumentado")
PY

echo "[+] Commit & push"
git add -A
git commit -m "fix(render_entry): clean interactions bootstrap + alias + diag/repair (indent OK)" || true
git push -u --force-with-lease origin "$(git rev-parse --abbrev-ref HEAD)"

cat <<'NEXT'

[•] Hecho. Ahora:
1) Espera a que Render haga el redeploy (o forzalo).
2) Verifica y repara esquema si hace falta:

APP="https://paste12-rmsk.onrender.com"

# Debe decir: "import_path": "render_entry:app"
curl -s "$APP/api/diag/import" | jq .

# Debe listar /api/notes/<id>/(like|view|stats) y /api/ix/...
curl -s "$APP/api/debug-urlmap" | jq '.rules | map(select(.rule|test("^/api/(notes|ix)/")))'

# Si todavía no existe la tabla de eventos, repárala:
curl -si -X POST "$APP/api/notes/repair-interactions" | sed -n '1,120p'

# Probar con un ID real:
ID=$(curl -s "$APP/api/notes?page=1" | jq -r '.[0].id'); echo "Usando ID=$ID"
curl -si -X POST "$APP/api/ix/notes/$ID/like"  | sed -n '1,120p'
curl -si -X POST "$APP/api/ix/notes/$ID/view"  | sed -n '1,120p'
curl -si      "$APP/api/ix/notes/$ID/stats"    | sed -n '1,160p'
NEXT
