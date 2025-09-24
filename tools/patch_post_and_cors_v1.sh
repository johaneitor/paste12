#!/usr/bin/env bash
set -euo pipefail

changed=0

# 1) backend/routes.py → asegurar que /api/notes acepta POST
if [[ -f backend/routes.py ]]; then
python - "$PWD/backend/routes.py" <<'PY'
import io,re,sys
p=sys.argv[1]
s=io.open(p,'r',encoding='utf-8').read()
orig=s

# Asegurar importaciones comunes
if "from flask import" in s:
    if "request" not in s:
        s=re.sub(r"from flask import ([^\n]+)", lambda m: \
            ("from flask import "+(m.group(1)+", request").replace(", request, request",", request")), s)
else:
    s="from flask import Blueprint, jsonify, request\n"+s

# Asegurar blueprint 'api'
if not re.search(r"api\s*=\s*Blueprint\(", s):
    s="from flask import Blueprint\napi=Blueprint('api',__name__)\n"+s

# Asegurar @api.route('/api/notes', methods=['GET'])
if not re.search(r"@api\.route\('/api/notes'", s):
    s += """

@api.route('/api/notes', methods=['GET'])
def list_notes():
    from backend.models import Note
    limit = 10
    try:
        from flask import request
        limit = int(request.args.get('limit', 10))
    except Exception:
        pass
    notes = Note.query.order_by(Note.timestamp.desc()).limit(limit).all()
    def ser(n): 
        return dict(id=n.id,text=n.text,timestamp=str(n.timestamp),
                    expires_at=str(n.expires_at) if getattr(n,'expires_at',None) else None,
                    likes=getattr(n,'likes',0),views=getattr(n,'views',0),reports=getattr(n,'reports',0),
                    author_fp=getattr(n,'author_fp',None))
    return jsonify([ser(n) for n in notes])
"""

# Asegurar endpoint POST
if not re.search(r"@api\.route\('/api/notes',\s*methods=\[.*POST.*\]\)", s, re.I|re.S):
    s += """

@api.route('/api/notes', methods=['POST'])
def create_note():
    from backend import db
    from backend.models import Note
    from flask import request, jsonify
    data = request.get_json(silent=True) or {}
    text = (data.get('text') or request.form.get('text') or '').strip()
    if not text:
        return ("missing text", 400)
    n = Note(text=text)
    db.session.add(n)
    db.session.commit()
    return jsonify({"ok": True, "id": n.id}), 201
"""

if s!=orig:
    io.open(p,'w',encoding='utf-8').write(s)
    print("[routes] parche aplicado: /api/notes GET/POST")
PY
    changed=1
else
    echo "WARN: no existe backend/routes.py (omito)"
fi

# 2) backend/__init__.py → asegurar CORS y registro del blueprint
if [[ -f backend/__init__.py ]]; then
python - "$PWD/backend/__init__.py" <<'PY'
import io,re,sys
p=sys.argv[1]
s=io.open(p,'r',encoding='utf-8').read()
orig=s

def ensure(line, block):
    return block in line

# import CORS
if "from flask_cors import CORS" not in s:
    s = "from flask_cors import CORS\n" + s

# create_app / app
if "def create_app(" not in s and "app = Flask(" not in s:
    s = "from flask import Flask\napp = Flask(__name__)\n"+s

# Instanciar CORS sobre app o en create_app
if "CORS(" not in s:
    s = re.sub(r"(app\s*=\s*Flask\([^)]+\))", r"\1\nCORS(app, resources={r'/api/*': {'origins': '*'}})", s, flags=re.S)

# Registrar blueprint api si existe
if "from backend.routes import api" not in s:
    s = "from backend.routes import api\n"+s
if not re.search(r"app\.register_blueprint\(\s*api\s*\)", s):
    s = re.sub(r"(app\s*=\s*Flask\([^)]+\).*)", r"\1\napp.register_blueprint(api)", s, flags=re.S)

# Health mínimo por si hiciera falta
if "def health()" not in s and "@app.route('/api/health')" not in s:
    s += """

@app.route('/api/health')
def health():
    return {"ok": True, "api": True, "ver": "wsgi-lazy-v2"}
"""

if s!=orig:
    io.open(p,'w',encoding='utf-8').write(s)
    print("[init] CORS/blueprint/health asegurados")
PY
    changed=1
else
    echo "WARN: no existe backend/__init__.py (omito)"
fi

# 3) Compilar
python -m py_compile backend/__init__.py 2>/dev/null && echo "py_compile backend/__init__.py OK" || { echo "py_compile FAIL"; exit 1; }

if [[ "$changed" -eq 0 ]]; then
  echo "INFO: nada que cambiar"
fi
echo "Listo. Haz deploy en Render."
