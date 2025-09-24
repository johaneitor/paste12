#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$(pwd)}"
cd "$ROOT"

echo "[+] Verificando/añadiendo psycopg2-binary en requirements.txt"
if [ -f requirements.txt ] && ! grep -qi '^psycopg2-binary' requirements.txt; then
  echo "psycopg2-binary" >> requirements.txt
  echo "    - agregado psycopg2-binary"
else
  echo "    - ok"
fi

FILE="render_entry.py"
[ -f "$FILE" ] || { echo "[!] No existe $FILE (se necesita render_entry.py)"; exit 1; }

echo "[+] Backup de $FILE"
cp -f "$FILE" "$FILE.bak.$(date +%s)"

echo "[+] Limpiando bloques viejos de interactions y reinsertando bootstrap limpio…"
python - <<'PY'
import re, io
p="render_entry.py"
s=open(p,"r",encoding="utf-8").read()

# Quitar bloques anteriores problemáticos
for pat in [
    r"# >>> interactions_module_autoreg[\s\S]*?# <<< interactions_module_autoreg",
    r"# --- interactions bootstrap.*?(?:\Z|# --- end interactions bootstrap)",
    r"# --- interactions bootstrap \(clean\) start ---[\s\S]*?\Z",
]:
    s=re.sub(pat,"# (old interactions bootstrap removed)",s,flags=re.M)

clean_block = r'''
# --- interactions bootstrap (CLEAN, idempotent) ---
try:
    from backend.modules.interactions import (
        bp as _ix_bp,
        alias_bp as _ix_alias_bp,
        ensure_schema as _ix_ensure_schema,
    )
except Exception as _e_ix:
    _ix_bp = None
    _ix_alias_bp = None
    def _ix_ensure_schema():
        return None

def _ix_register_blueprints(_app):
    try:
        if _ix_ensure_schema:
            with _app.app_context():
                _ix_ensure_schema()
        if _ix_bp is not None:
            try: _app.register_blueprint(_ix_bp, url_prefix="/api")
            except Exception: pass
        if _ix_alias_bp is not None:
            try: _app.register_blueprint(_ix_alias_bp, url_prefix="/api")
            except Exception: pass
    except Exception:
        pass

try:
    _ix_register_blueprints(app)
except Exception:
    pass

from flask import Blueprint as _IXBP, jsonify as _jsonify
_ixdiag = _IXBP("ixdiag_render_entry", __name__)

@_ixdiag.get("/notes/diag")
def _ix_notes_diag():
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
            out["total_likes"] = int(likes_cnt); out["total_views"] = int(views_cnt)
        return _jsonify(ok=True, **out), 200
    except Exception as e:
        return _jsonify(ok=False, error="diag_failed", detail=str(e)), 500

@_ixdiag.post("/notes/repair-interactions")
def _ix_repair_interactions():
    try:
        if _ix_ensure_schema:
            with app.app_context():
                _ix_ensure_schema()
        return _jsonify(ok=True, repaired=True), 200
    except Exception as e:
        return _jsonify(ok=False, error="repair_failed", detail=str(e)), 500

try:
    app.register_blueprint(_ixdiag, url_prefix="/api")
except Exception:
    pass
# --- end interactions bootstrap
'''
s = s.rstrip()+"\n\n"+clean_block+"\n"
open(p,"w",encoding="utf-8").write(s)
print("[OK] render_entry.py saneado e instrumentado")
PY

echo "[+] Commit & push"
git add -A
git commit -m "fix(render_entry): clean interactions bootstrap + diag + ensure_schema + psycopg2-binary check" || true
git push -u --force-with-lease origin "$(git rev-parse --abbrev-ref HEAD)"

cat <<'NEXT'

[i] Hecho. Ahora:
1) En Render usa Start Command:
   gunicorn -w ${WEB_CONCURRENCY:-2} -k gthread --threads ${THREADS:-4} -b 0.0.0.0:$PORT render_entry:app

2) Verificación (pégalos luego del redeploy):
   APP="${RENDER_URL:-https://paste12-rmsk.onrender.com}"
   echo "[import]"; curl -s "$APP/api/diag/import" | jq .
   echo "[map]";    curl -s "$APP/api/debug-urlmap" | jq '.rules | map(select(.rule|test("^/api/(notes|ix)/")))'
   echo "[diag]";   curl -s "$APP/api/notes/diag" | jq .

   ID=$(curl -s "$APP/api/notes?page=1" | jq -r '.[0].id // empty'); echo "ID=$ID"
   if [ -z "$ID" ]; then
     ID=$(curl -s -X POST -H 'Content-Type: application/json' \
           -d '{"text":"probe","hours":24}' "$APP/api/notes" | jq -r '.id')
     echo "ID nuevo=$ID"
   fi

   curl -si -X POST "$APP/api/ix/notes/$ID/like"  | sed -n '1,120p'
   curl -si -X POST "$APP/api/ix/notes/$ID/view"  | sed -n '1,120p'
   curl -si      "$APP/api/ix/notes/$ID/stats"    | sed -n '1,160p'
NEXT
