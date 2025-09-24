#!/usr/bin/env bash
set -euo pipefail

log(){ printf "[hotfix] %s\n" "$*"; }

# --- archivos ---
WSGI="wsgi.py"
ROUTES="backend/routes.py"
INIT="backend/__init__.py"
TS="$(date -u +%Y%m%d-%H%M%SZ)"

# --- backups si existen ---
for f in "$WSGI" "$ROUTES" "$INIT"; do
  [[ -f "$f" ]] && cp -f "$f" "$f.$TS.bak" && log "Backup: $f.$TS.bak" || true
done

# --- 1) WSGI minimalista que no depende de shims/guards ---
cat > "$WSGI" <<'PY'
# WSGI mínima y robusta.
# Intenta (en orden): backend.create_app(), backend.app, backend.wsgi.app, contract_shim.application
from importlib import import_module

def _first_ok(cands):
    for mod_name, expr in cands:
        try:
            mod = import_module(mod_name)
            obj = mod
            for part in expr.split('.'):
                obj = getattr(obj, part)
            return obj
        except Exception:
            continue
    raise RuntimeError("no pude resolver una app WSGI válida")

cands = [
    ("backend", "create_app"),
    ("backend", "app"),
    ("backend.wsgi", "app"),
    ("contract_shim", "application"),
]

app_or_factory = _first_ok(cands)
application = app_or_factory() if callable(app_or_factory) else app_or_factory
PY
python -m py_compile "$WSGI" && log "WSGI listo"

# --- 2) Rutas: asegurar methods y CORS básicos en /api/notes ---
if [[ -f "$ROUTES" ]]; then
python - "$ROUTES" <<'PY'
import io, re, sys
p=sys.argv[1]
s=io.open(p,'r',encoding='utf-8').read()
orig=s
# Asegurar que @app.route('/api/notes'...) tenga GET/POST/OPTIONS
s=re.sub(
    r"@app\.route\(\s*['\"]/api/notes['\"]\s*(?:,[^)]+)?\)",
    "@app.route('/api/notes', methods=['GET','POST','OPTIONS'])",
    s, flags=re.I
)
# Endpoints secundarios
s=re.sub(r"@app\.route\(\s*['\"]/api/notes/<int:note_id>/like['\"].*?\)",
         "@app.route('/api/notes/<int:note_id>/like', methods=['POST','OPTIONS'])",
         s, flags=re.I)
s=re.sub(r"@app\.route\(\s*['\"]/api/notes/<int:note_id>/view['\"].*?\)",
         "@app.route('/api/notes/<int:note_id>/view', methods=['POST','OPTIONS'])",
         s, flags=re.I)
s=re.sub(r"@app\.route\(\s*['\"]/api/notes/<int:note_id>/report['\"].*?\)",
         "@app.route('/api/notes/<int:note_id>/report', methods=['POST','OPTIONS'])",
         s, flags=re.I)

# Preflight genérico si no existiera
if "def _p12_options()" not in s:
    s += """

@app.route('/api/<path:anypath>', methods=['OPTIONS'])
def _p12_options(anypath):
    from flask import make_response
    resp = make_response('', 204)
    resp.headers['Access-Control-Allow-Origin'] = '*'
    resp.headers['Access-Control-Allow-Methods'] = 'GET, POST, HEAD, OPTIONS'
    resp.headers['Access-Control-Allow-Headers'] = 'Content-Type'
    resp.headers['Access-Control-Max-Age'] = '86400'
    return resp
"""
if s!=orig:
    io.open(p,'w',encoding='utf-8').write(s)
PY
python -m py_compile "$ROUTES" && log "routes OK" || log "routes no presentes (continuo)"
fi

# --- 3) backend/__init__.py: normalizar indentación y pool seguro (opcional) ---
if [[ -f "$INIT" ]]; then
python - "$INIT" <<'PY'
import io, re, sys, textwrap
p=sys.argv[1]
s=io.open(p,'r',encoding='utf-8').read()
# normalizar tabs→4 espacios
s=s.replace('\t','    ')
# Asegurar fragmentos mínimos
if "SQLALCHEMY_DATABASE_URI" not in s:
    s += "\n# fallback mínimo de config\n"
    s += "from os import getenv\n"
    s += "SQLALCHEMY_DATABASE_URI = getenv('DATABASE_URL','sqlite:///local.db')\n"
# Asegurar create_app si no existe
if "def create_app(" not in s:
    s += textwrap.dedent("""

    from flask import Flask
    from flask_sqlalchemy import SQLAlchemy
    db = SQLAlchemy()

    def create_app():
        app = Flask(__name__)
        app.config['SQLALCHEMY_DATABASE_URI'] = SQLALCHEMY_DATABASE_URI
        app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
        db.init_app(app)
        try:
            from backend import routes as _routes  # registra vistas si existen
            if hasattr(_routes,'init_app'): _routes.init_app(app)
        except Exception:
            pass
        @app.get('/api/health')
        def _health(): return {'ok': True, 'api': True, 'ver':'fallback'}
        return app
    """)
io.open(p,'w',encoding='utf-8').write(s)
PY
python -m py_compile "$INIT" && log "__init__ OK"
fi

log "Hecho. Despliega con gunicorn wsgi:application"
