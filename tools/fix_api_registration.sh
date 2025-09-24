#!/usr/bin/env bash
set -Eeuo pipefail

WSGI="wsgi.py"
cp -a "$WSGI" "$WSGI.bak.$(date +%s)" 2>/dev/null || true

python - "$WSGI" <<'PY'
import io, sys
p = sys.argv[1]
s = io.open(p, 'r', encoding='utf-8').read()

block = r"""
# --- Ensure API blueprint is attached in prod ---
try:
    from backend.routes import api as _api_bp  # type: ignore
    if hasattr(app, "register_blueprint"):
        if "api" not in getattr(app, "blueprints", {}):
            app.register_blueprint(_api_bp)  # type: ignore[attr-defined]
except Exception as _e:
    # Log suave (stdout) para ver el motivo en Render si falla
    print("[wsgi] failed to attach backend.routes.api:", _e)
"""

if "from backend.routes import api as _api_bp" not in s:
    s = s.rstrip() + "\n" + block + "\n"
    io.open(p, 'w', encoding='utf-8').write(s)
    print("patched")
else:
    print("already present")
PY

git add wsgi.py || true
git commit -m "wsgi: attach backend.routes.api blueprint explicitly" || true
git push origin main
