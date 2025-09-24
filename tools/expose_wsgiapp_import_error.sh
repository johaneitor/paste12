#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"

FILE="wsgiapp/__init__.py"
[ -f "$FILE" ] || { echo "[!] No existe $FILE. Abortando."; exit 1; }

echo "[+] Backup de $FILE"
cp -f "$FILE" "$FILE.bak.$(date +%s)"

python - <<'PY'
import re, io, sys
p="wsgiapp/__init__.py"
s=open(p,"r",encoding="utf-8").read()

if "WSGIAPP_IMPORT_PATH" not in s:
    inject = r'''
# === import diag: expone el camino de carga y el último error de importación ===
WSGIAPP_IMPORT_PATH = None
WSGIAPP_IMPORT_ERROR = None

def _try_import_real_app():
    global WSGIAPP_IMPORT_PATH, WSGIAPP_IMPORT_ERROR, app
    try:
        from render_entry import app as _app
        app = _app
        WSGIAPP_IMPORT_PATH = "render_entry:app"
        return True
    except Exception as e1:
        WSGIAPP_IMPORT_ERROR = f"render_entry failed: {e1!r}"
        try:
            from wsgi import app as _app2
            app = _app2
            WSGIAPP_IMPORT_PATH = "wsgi:app"
            return True
        except Exception as e2:
            WSGIAPP_IMPORT_ERROR = (WSGIAPP_IMPORT_ERROR or "") + f" | wsgi failed: {e2!r}"
            return False

# Si tu __init__ antes hacía import aquí, sustitúyelo por:
_loaded = _try_import_real_app()
'''
    # Inserta al principio, justo después de imports top-level (buscamos la primera línea en blanco doble)
    s = inject + "\n" + s

# Añadir endpoints de diagnóstico si faltan
if "wsgiapp_diag_import" not in s:
    diag = r'''
try:
    from flask import Blueprint, jsonify
    _diag_imp = Blueprint("wsgiapp_diag_import", __name__)

    @_diag_imp.get("/diag/import", endpoint="wsgiapp_diag_import")
    def _wsgiapp_diag_import():
        info = {
            "ok": True,
            "import_path": WSGIAPP_IMPORT_PATH,
            "fallback": (WSGIAPP_IMPORT_PATH is None),
        }
        if WSGIAPP_IMPORT_ERROR:
            info["import_error"] = WSGIAPP_IMPORT_ERROR
        return jsonify(info), 200

    @_diag_imp.get("/diag/urlmap", endpoint="wsgiapp_diag_urlmap")
    def _wsgiapp_diag_urlmap():
        rules=[]
        for r in app.url_map.iter_rules():
            methods = sorted([m for m in r.methods if m not in ("HEAD","OPTIONS")])
            rules.append({"rule": str(r), "endpoint": r.endpoint, "methods": methods})
        return jsonify(ok=True, rules=rules), 200

    try:
        app.register_blueprint(_diag_imp, url_prefix="/api")
    except Exception:
        pass
except Exception:
    pass
'''
    s = s.rstrip() + "\n" + diag

open(p,"w",encoding="utf-8").write(s)
print("[OK] wsgiapp/__init__.py parcheado con diagnóstico de import")
PY

echo "[+] Commit & push"
git add -A
git commit -m "chore(wsgiapp): expose import path/error at /api/diag/import and /api/diag/urlmap" || true
git push -u --force-with-lease origin "$(git rev-parse --abbrev-ref HEAD)"

echo
echo "[i] Luego de redeploy, ejecuta:"
cat <<'CMD'
curl -s https://paste12-rmsk.onrender.com/api/diag/import | jq .
curl -s https://paste12-rmsk.onrender.com/api/diag/urlmap | jq .
CMD
