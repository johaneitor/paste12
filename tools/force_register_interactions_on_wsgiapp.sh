#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"

FILE="wsgiapp/__init__.py"
[ -f "$FILE" ] || { echo "[!] No existe $FILE. Abortando."; exit 1; }

echo "[+] Backup de $FILE"
cp -f "$FILE" "$FILE.bak.$(date +%s)"

python - <<'PY'
import re, os, io, sys
p="wsgiapp/__init__.py"
s=open(p,"r",encoding="utf-8").read()

# 1) Aseguramos que SIEMPRE, tras tener 'app', registremos interactions (bp y alias_bp).
patch = r'''
# --- interactions: registro forzado sobre wsgiapp.app ---
try:
    # Normalizar DATABASE_URL (soporta postgres:// -> postgresql://)
    import os
    url = os.environ.get("DATABASE_URL","")
    if url.startswith("postgres://"):
        os.environ["DATABASE_URL"] = "postgresql://" + url[len("postgres://"):]
except Exception:
    pass

try:
    from backend.modules.interactions import bp as interactions_bp, alias_bp
    from flask import current_app as _cap
    _app = None
    try:
        _app = _cap._get_current_object()
    except Exception:
        pass
    if _app is None:
        try:
            _app = app
        except Exception:
            _app = None
    def _has_rule(_a, path, method):
        try:
            for r in _a.url_map.iter_rules():
                if str(r)==path and method.upper() in r.methods:
                    return True
        except Exception:
            pass
        return False
    if _app is not None:
        need_like  = not _has_rule(_app, "/api/notes/<int:note_id>/like",  "POST")
        need_view  = not _has_rule(_app, "/api/notes/<int:note_id>/view",  "POST")
        need_stats = not _has_rule(_app, "/api/notes/<int:note_id>/stats", "GET")
        need_alias = not _has_rule(_app, "/api/ix/notes/<int:note_id>/like","POST")
        if need_like or need_view or need_stats:
            _app.register_blueprint(interactions_bp, url_prefix="/api")
        if need_alias:
            _app.register_blueprint(alias_bp, url_prefix="/api")
        # create_all() para garantizar tablas
        try:
            from backend import db as _db
            with _app.app_context():
                _db.create_all()
        except Exception:
            try:
                from flask_sqlalchemy import SQLAlchemy
                _db = SQLAlchemy(_app)
                with _app.app_context():
                    _db.create_all()
            except Exception:
                pass
except Exception:
    # no rompemos el arranque si falla
    pass
# --- /interactions ---
'''

# Idempotencia: si ya está agregado, no duplicar
if "interactions: registro forzado" not in s:
    # Insertamos al final del archivo
    s = s.rstrip() + "\n" + patch

# 2) Asegurar /api/health y /api/debug-urlmap (por si el fallback no los tenía)
if "/api/debug-urlmap" not in s or "bridge_probe.debug_urlmap" in s:
    add_diag = r'''
# --- diag endpoints mínimos sobre wsgiapp.app ---
try:
    from flask import Blueprint, jsonify
    _diag = Blueprint("wsgiapp_diag", __name__)
    @_diag.get("/health", endpoint="wsgiapp_health")
    def _wsgiapp_health():
        return jsonify(ok=True, note="wsgiapp"), 200
    @_diag.get("/debug-urlmap", endpoint="wsgiapp_debug_urlmap")
    def _wsgiapp_debug():
        rules=[]
        try:
            for r in app.url_map.iter_rules():
                methods = sorted([m for m in r.methods if m not in ("HEAD","OPTIONS")])
                rules.append({"rule": str(r), "endpoint": r.endpoint, "methods": methods})
        except Exception as e:
            return jsonify(ok=False, error=str(e)), 500
        return jsonify(ok=True, rules=rules), 200
    try:
        app.register_blueprint(_diag, url_prefix="/api")
    except Exception:
        pass
except Exception:
    pass
# --- /diag ---
'''
    s = s.rstrip() + "\n" + add_diag

open(p,"w",encoding="utf-8").write(s)
print("[OK] wsgiapp/__init__.py parchado")
PY

echo "[+] Commit & push"
git add -A
git commit -m "fix(wsgiapp): force-register interactions bp/alias, normalize DATABASE_URL, ensure create_all, add diag" || true
git push -u --force-with-lease origin "$(git rev-parse --abbrev-ref HEAD)"

cat <<'NEXT'

[i] Ahora redeploy en Render (Start Command debe seguir apuntando a: 
    gunicorn -w ${WEB_CONCURRENCY:-2} -k gthread --threads ${THREADS:-4} -b 0.0.0.0:$PORT wsgiapp:app)

Luego verifica con:
  curl -s https://paste12-rmsk.onrender.com/api/health | jq .
  curl -s https://paste12-rmsk.onrender.com/api/debug-urlmap | jq .

Y testea los endpoints nuevos (alias seguros):
  curl -i -s -X POST https://paste12-rmsk.onrender.com/api/ix/notes/1/like
  curl -i -s -X POST https://paste12-rmsk.onrender.com/api/ix/notes/1/view
  curl -i -s https://paste12-rmsk.onrender.com/api/ix/notes/1/stats

Si /api/health te devuelve "wsgiapp" y el url-map lista /api/notes <like|view|stats> (o /api/ix/...), quedó operativo.
NEXT
