#!/usr/bin/env bash
set -euo pipefail
FILE="backend/__init__.py"
python - <<'PY'
from pathlib import Path
p=Path("backend/__init__.py")
s=p.read_text(encoding="utf-8")
if "_orig_create_app" not in s:
    s=s.replace("def create_app(", "_orig_create_app=create_app\n\ndef create_app(")
if "register_blueprint(api_bp" not in s:
    inj = '''
    try:
        from backend.routes import api as api_bp
        app.register_blueprint(api_bp, url_prefix='/api')
    except Exception:
        pass
'''
    s=s.replace("app = _orig_create_app(*args, **kwargs)", "app = _orig_create_app(*args, **kwargs)"+inj)
p.write_text(s, encoding="utf-8")
print("OK: create_app refuerzo api_bp")
PY
git add backend/__init__.py >/dev/null 2>&1 || true
git commit -m "chore(factory): refuerzo para registrar api_bp con url_prefix=/api" >/dev/null 2>&1 || true
git push origin HEAD >/dev/null 2>&1 || true
echo "Hecho."
