#!/usr/bin/env bash
set -euo pipefail

INI="backend/__init__.py"
SAFE="backend/safeguards.py"
TS="$(date -u +%Y%m%d-%H%M%SZ)"

[[ -f "$INI" ]] || { echo "ERROR: falta $INI"; exit 1; }
cp -f "$INI" "$INI.$TS.bak"
echo "[backup] $INI.$TS.bak"

# 1) Escribir/actualizar backend/safeguards.py (idempotente)
mkdir -p backend
cat > "$SAFE" <<'PY'
from __future__ import annotations
from flask import request, jsonify, make_response

def register_api_safeguards(app):
    # 1) Preflight CORS universal para /api/* (204 sin tocar DB)
    @app.before_request
    def _skip_options_preflight():
        if request.method == 'OPTIONS' and request.path.startswith('/api/'):
            resp = make_response(('', 204))
            h = resp.headers
            h['Access-Control-Allow-Origin'] = '*'
            h['Access-Control-Allow-Methods'] = 'GET, POST, HEAD, OPTIONS'
            h['Access-Control-Allow-Headers'] = 'Content-Type'
            h['Access-Control-Max-Age'] = '86400'
            return resp

    # 2) OPTIONS /api/notes si no existe (normalmente lo intercepta el before_request)
    try:
        exists_opt = any((r.rule == '/api/notes' and 'OPTIONS' in r.methods) for r in app.url_map.iter_rules())
    except Exception:
        exists_opt = False
    if not exists_opt:
        app.add_url_rule('/api/notes', 'api_notes_options_safe',
                         lambda: make_response(('', 204)), methods=['OPTIONS'])

    # 3) Fallback GET /api/notes si no existe (no pisa tu route real)
    try:
        exists_get = any((r.rule == '/api/notes' and 'GET' in r.methods) for r in app.url_map.iter_rules())
    except Exception:
        exists_get = False
    if not exists_get:
        def _api_notes_fallback():
            limit = 10
            try:
                limit = min(max(int(request.args.get('limit', 10)), 1), 50)
            except Exception:
                limit = 10
            data = []
            link = None
            try:
                from .models import Note  # lazy import para evitar ciclos
                rows = Note.query.order_by(getattr(Note, 'timestamp').desc()).limit(limit).all()
                for n in rows:
                    data.append({
                        'id': getattr(n, 'id', None),
                        'text': getattr(n, 'text', ''),
                        'timestamp': getattr(n, 'timestamp', None),
                        'likes': getattr(n, 'likes', 0),
                        'views': getattr(n, 'views', 0),
                    })
                if data and data[-1].get('id') is not None:
                    base = request.url_root.rstrip('/')
                    link = f"{base}/api/notes?limit={limit}&before_id={data[-1]['id']}"
            except Exception as ex:
                try:
                    app.logger.warning('fallback /api/notes (db issue): %r', ex)
                except Exception:
                    pass
            resp = jsonify(data)
            resp.headers['Access-Control-Allow-Origin'] = '*'
            if link:
                resp.headers['Link'] = f"<{link}>; rel=\"next\""
            return resp, 200
        app.add_url_rule('/api/notes', 'api_notes_fallback_safe', _api_notes_fallback, methods=['GET'])
PY

# 2) Parchear __init__.py (normaliza indentación, asegura imports y registra safeguards)
python - <<'PY'
import io, re, sys, pathlib
p = pathlib.Path("backend/__init__.py")
s = p.read_text(encoding="utf-8")

orig = s
# Normalizar tabs -> 4 espacios (evita IndentationError)
s = s.replace("\t", "    ")

def ensure_future(s):
    # Asegura from __future__ arriba del todo
    lines = s.splitlines()
    if lines and not lines[0].startswith("from __future__ import annotations"):
        # Quitar futura(s) repetidas en otro lado
        lines = [ln for ln in lines if not ln.strip().startswith("from __future__ import annotations")]
        lines.insert(0, "from __future__ import annotations")
        s2 = "\n".join(lines)
        return s2
    return s

def ensure_import(s, imp):
    if imp in s: return s
    # Inserta después del primer 'from flask import' o del primer import visible
    m = re.search(r"^from flask import .*$", s, flags=re.M)
    if m:
        idx = m.end()
        return s[:idx] + "\n" + imp + s[idx:]
    return "import typing\n" + imp + "\n" + s

s = ensure_future(s)
s = ensure_import(s, "from flask_cors import CORS")
s = ensure_import(s, "from .safeguards import register_api_safeguards")

# Reparar/crear handler _api_unavailable con cuerpo válido (a nivel módulo)
if re.search(r"^def\s+_api_unavailable\s*\(", s, flags=re.M):
    s = re.sub(
        r"^def\s+_api_unavailable\s*\([^)]*\)\s*:[\s\S]*?(?=^\S|^$)",
        ("def _api_unavailable(e: Exception):\n"
         "    from flask import request, jsonify, current_app\n"
         "    try:\n"
         "        current_app.logger.exception(\"API error on %s %s\", request.method, request.path)\n"
         "    except Exception:\n"
         "        pass\n"
         "    return jsonify(error=\"internal_error\", detail=str(e)), 500\n\n"),
        s, flags=re.M)
else:
    s = s + ("\n\ndef _api_unavailable(e: Exception):\n"
             "    from flask import request, jsonify, current_app\n"
             "    try:\n"
             "        current_app.logger.exception(\"API error on %s %s\", request.method, request.path)\n"
             "    except Exception:\n"
             "        pass\n"
             "    return jsonify(error=\"internal_error\", detail=str(e)), 500\n")

# Insertar CORS(app, ...) y register_api_safeguards(app) tras 'app = Flask(...)'
def inject_after_app_creation(s):
    # localizar la línea 'app = Flask(' y su indentación
    m = re.search(r"^(\s*)app\s*=\s*Flask\([^)]*\)\s*$", s, flags=re.M)
    if not m:
        return s
    indent = m.group(1)
    block = (
        f"{indent}CORS(app, resources={{r\"/api/*\": {{\"origins\": \"*\"}}}}, "
        f"methods=[\"GET\",\"POST\",\"HEAD\",\"OPTIONS\"], "
        f"allow_headers=[\"Content-Type\"], max_age=86400)\n"
        f"{indent}register_api_safeguards(app)\n"
    )
    # Evitar duplicados
    if "register_api_safeguards(app)" in s:
        return s
    # Insertar justo después de la línea encontrada
    idx = m.end()
    return s[:idx] + "\n" + block + s[idx:]

s = inject_after_app_creation(s)

# Asegurar que existe 'return app' (por si una edición lo dañó)
if not re.search(r"^\s*return\s+app\s*$", s, flags=re.M):
    # Insertar un return app al final de create_app si existe, si no, add noop
    m = re.search(r"^def\s+create_app\s*\([^)]*\)\s*:\s*$", s, flags=re.M)
    if m:
        # insertar '    return app' antes del próximo 'def ' o fin
        tail = s[m.end():]
        # si ya hay app = Flask, asumimos indentación de 4 espacios
        s = s + "\n    return app\n"
    else:
        s = s + "\n# NOTE: create_app ausente; no se modifica el flujo.\n"

if s != orig:
    p.write_text(s, encoding="utf-8")
    print("[patch] backend/__init__.py actualizado")
else:
    print("[info] backend/__init__.py ya estaba OK")
PY

# 3) Sanity
python -m py_compile "$INI" "$SAFE"
echo "py_compile OK"

echo "Listo. Despliega o prueba localmente:"
echo "  curl -i -X OPTIONS https://paste12-rmsk.onrender.com/api/notes"
echo "  curl -i https://paste12-rmsk.onrender.com/api/notes?limit=10 | head -n1"
