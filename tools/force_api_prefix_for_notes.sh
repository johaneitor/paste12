#!/usr/bin/env bash
set -euo pipefail
_red(){ printf "\033[31m%s\033[0m\n" "$*"; }
_grn(){ printf "\033[32m%s\033[0m\n" "$*"; }

ROUTES="backend/routes.py"
INIT="backend/__init__.py"
[[ -f "$ROUTES" ]] || { _red "No existe $ROUTES"; exit 1; }
[[ -f "$INIT"   ]] || { _red "No existe $INIT"; exit 1; }

python - <<'PY'
from pathlib import Path
import re
rp = Path("backend/routes.py")
sp = rp.read_text(encoding="utf-8")

# --- 1) Normalizar blueprint api sin url_prefix ---
sp = re.sub(
    r'api\s*=\s*Blueprint\(\s*"api"\s*,\s*__name__(?:\s*,\s*url_prefix\s*=\s*["\'][^"\']+["\'])?\s*\)',
    'api = Blueprint("api", __name__)',
    sp,
    flags=re.M
)

# --- 2) Migrar @app.route("/notes*") a @api.route("/notes*") ---
for pat in [
    r'@app\.route\("/notes"',
    r'@app\.route\("/notes/<int:note_id>"',
    r'@app\.route\("/notes/<int:note_id>/view"',
    r'@app\.route\("/notes/<int:note_id>/like"',
    r'@app\.route\("/notes/<int:note_id>/report"',
]:
    sp = re.sub(pat, pat.replace("@app.route","@api.route"), sp)

# --- 3) Migrar health/_routes si estaban con @app.route ---
sp = re.sub(r'@app\.route\("/health"',  '@api.route("/health"',  sp)
sp = re.sub(r'@app\.route\("/_routes"', '@api.route("/_routes"', sp)

# --- 4) Asegurar ping ---
if '@api.route("/ping"' not in sp:
    block = '''
@api.route("/ping", methods=["GET"])
def api_ping():
    return jsonify({"pong": True}), 200
'''
    if not sp.endswith("\n"): sp += "\n"
    sp += block

rp.write_text(sp, encoding="utf-8")

# --- 5) Refuerzo en factory: registrar api con url_prefix="/api" ---
ip = Path("backend/__init__.py")
isrc = ip.read_text(encoding="utf-8")
if "_orig_create_app" not in isrc:
    isrc = isrc.replace("def create_app(", "_orig_create_app = create_app\n\ndef create_app(")
if "register_blueprint(api_bp, url_prefix='/api')" not in isrc:
    inj = '''
    try:
        from backend.routes import api as api_bp
        app.register_blueprint(api_bp, url_prefix='/api')
    except Exception:
        pass
'''
    isrc = isrc.replace("app = _orig_create_app(*args, **kwargs)", "app = _orig_create_app(*args, **kwargs)"+inj)
ip.write_text(isrc, encoding="utf-8")

print("OK: migrados decoradores de notas y asegurado registro con /api")
PY

git add backend/routes.py backend/__init__.py >/dev/null 2>&1 || true
git commit -m "hotfix(api): migra /notes* y helpers a blueprint api; asegura registro con url_prefix=/api" >/dev/null 2>&1 || true
git push origin HEAD >/dev/null 2>&1 || true
_grn "✓ Commit & push hechos."
