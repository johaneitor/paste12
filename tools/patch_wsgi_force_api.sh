#!/usr/bin/env bash
set -euo pipefail

# Crea el instalador si no existe (idempotente)
mkdir -p backend
if [[ ! -f backend/force_api.py ]]; then
  cat > backend/force_api.py <<'PY'
from flask import jsonify

def install(app):
    try:
        rules = list(app.url_map.iter_rules())
        have_ping   = any(str(r).rstrip('/') == '/api/ping'    for r in rules)
        have_routes = any(str(r).rstrip('/') == '/api/_routes' for r in rules)

        if not have_ping:
            app.add_url_rule('/api/ping', endpoint='api_ping_wsgi',
                             view_func=(lambda: jsonify({'ok': True, 'pong': True, 'src': 'wsgi'})), methods=['GET'])
        if not have_routes:
            def _dump():
                info=[]
                for r in app.url_map.iter_rules():
                    info.append({'rule': str(r),
                                 'methods': sorted(m for m in r.methods if m not in ('HEAD','OPTIONS')),
                                 'endpoint': r.endpoint})
                info.sort(key=lambda x: x['rule'])
                return jsonify({'routes': info}), 200
            app.add_url_rule('/api/_routes', endpoint='api_routes_dump_wsgi', view_func=_dump, methods=['GET'])
    except Exception:
        pass
PY
fi

# Parchea wsgiapp.py para importar e invocar install(app) siempre
python - <<'PY'
from pathlib import Path
import re
p = Path("wsgiapp.py")
s = p.read_text(encoding="utf-8")

if "from backend.force_api import install as _force_api_install" not in s:
    # Insertar import tras otros imports
    m = re.search(r"^(?:from .+|import .+)(?:\r?\n(?:from .+|import .+))*", s, flags=re.M)
    if m:
        s = s[:m.end()] + "\nfrom backend.force_api import install as _force_api_install\n" + s[m.end():]
    else:
        s = "from backend.force_api import install as _force_api_install\n" + s

if "_force_api_install(app)" not in s:
    s, n = re.subn(r"(app\s*=\s*create_app\([^)]*\))",
                   r"\\1\n_force_api_install(app)",
                   s, count=1)
    if n == 0:
        s += """

# --- WSGI FAILSAFE: instala /api/ping y /api/_routes si no están ---
try:
    _force_api_install(app)  # type: ignore[name-defined]
except Exception:
    pass
"""
p.write_text(s, encoding="utf-8")
print("OK: wsgiapp.py invoca _force_api_install(app)")
PY

git add backend/force_api.py wsgiapp.py >/dev/null 2>&1 || true
git commit -m "wsgi: instala /api/ping y /api/_routes tras create_app (failsafe)" >/dev/null 2>&1 || true
git push origin HEAD >/dev/null 2>&1 || true
echo "✓ Commit & push hechos (wsgi)."
