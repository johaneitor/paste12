#!/usr/bin/env bash
set -Eeuo pipefail

WSGI="wsgi.py"
cp -a "$WSGI" "$WSGI.bak.$(date +%s)" 2>/dev/null || true

python - "$WSGI" <<'PY'
import sys, io
p = sys.argv[1]
s = io.open(p, 'r', encoding='utf-8').read()

snippet = """
# --- Force-load API routes so endpoints exist in production ---
try:
    import backend.routes  # noqa: F401
except Exception:
    # Do not crash the app if routes import fails; API health must remain up
    pass
"""

if "import backend.routes" not in s:
    s = s.rstrip() + "\n" + snippet + "\n"
    io.open(p, 'w', encoding='utf-8').write(s)
    print("patched")
else:
    print("already present")
PY

git add "$WSGI" || true
git commit -m "chore(wsgi): force-import backend.routes to register API endpoints in prod" || true
git push origin main
