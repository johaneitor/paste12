#!/usr/bin/env bash
set -euo pipefail

P="backend/__init__.py"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
[[ -f "$P" ]] || { echo "ERROR: falta $P"; exit 1; }
cp -f "$P" "${P}.${TS}.bak"
echo "[backup] ${P}.${TS}.bak"

python - <<'PY'
import io, re, sys, os
p="backend/__init__.py"
s=io.open(p,"r",encoding="utf-8").read()
orig=s

def ensure_import(s, modline, anchor="from flask import"):
    if modline in s: return s
    # Insert justo encima de "from flask import"
    s = s.replace(anchor, modline+"\n"+anchor)
    return s

# 1) Asegurar import de CORS
s = ensure_import(s, "from flask_cors import CORS")

# 2) Arreglar handler _api_unavailable(e) si está mal definido
s = re.sub(
    r"def\s+_api_unavailable\s*\([^)]*\)\s*:[\s\S]*?(?=^\S|^$)",
    (
        "def _api_unavailable(e: Exception):\n"
        "    from flask import request, jsonify, current_app\n"
        "    try:\n"
        "        current_app.logger.exception(\"API error on %s %s\", request.method, request.path)\n"
        "    except Exception:\n"
        "        pass\n"
        "    return jsonify(error=\"internal_error\", detail=str(e)), 500\n\n"
    ),
    s, flags=re.M
)

# 3) Insertar CORS(app, ...) tras crear app = Flask(...)
if "CORS(app" not in s:
    s = re.sub(
        r"(app\s*=\s*Flask\([^)]*\)\s*\n)",
        r"\1    CORS(app, resources={r\"/api/*\": {\"origins\": \"*\"}}, methods=[\"GET\",\"POST\",\"HEAD\",\"OPTIONS\"], allow_headers=[\"Content-Type\"], max_age=86400)\n",
        s
    )

# 4) Insertar skip de preflight OPTIONS en /api/* ANTES del return app
injection = (
    "    @app.before_request\n"
    "    def _skip_options_preflight():\n"
    "        from flask import request, make_response\n"
    "        if request.method == 'OPTIONS' and request.path.startswith('/api/'):\n"
    "            resp = make_response(('', 204))\n"
    "            h = resp.headers\n"
    "            h['Access-Control-Allow-Origin'] = '*'\n"
    "            h['Access-Control-Allow-Methods'] = 'GET, POST, HEAD, OPTIONS'\n"
    "            h['Access-Control-Allow-Headers'] = 'Content-Type'\n"
    "            h['Access-Control-Max-Age'] = '86400'\n"
    "            return resp\n\n"
    "    # --- API guards / fallbacks ---\n"
    "    def _api_options_ok():\n"
    "        from flask import make_response\n"
    "        resp = make_response(('', 204))\n"
    "        h = resp.headers\n"
    "        h['Access-Control-Allow-Origin'] = '*'\n"
    "        h['Access-Control-Allow-Methods'] = 'GET, POST, HEAD, OPTIONS'\n"
    "        h['Access-Control-Allow-Headers'] = 'Content-Type'\n"
    "        h['Access-Control-Max-Age'] = '86400'\n"
    "        return resp\n\n"
    "    def _api_notes_fallback():\n"
    "        # Se usa SOLO si no existe un GET /api/notes ya registrado\n"
    "        from flask import request, jsonify, current_app\n"
    "        limit = 10\n"
    "        try:\n"
    "            limit = min(max(int(request.args.get('limit', 10)),1), 50)\n"
    "        except Exception:\n"
    "            limit = 10\n"
    "        data = []\n"
    "        link = None\n"
    "        try:\n"
    "            # Import lazy para evitar ciclos\n"
    "            from backend.models import Note, db\n"
    "            rows = Note.query.order_by(Note.timestamp.desc()).limit(limit).all()\n"
    "            for n in rows:\n"
    "                item = {\n"
    "                    'id': getattr(n, 'id', None),\n"
    "                    'text': getattr(n, 'text', ''),\n"
    "                    'timestamp': getattr(n, 'timestamp', None),\n"
    "                    'likes': getattr(n, 'likes', 0),\n"
    "                    'views': getattr(n, 'views', 0)\n"
    "                }\n"
    "                data.append(item)\n"
    "            if data and data[-1].get('id') is not None:\n"
    "                base = request.url_root.rstrip('/')\n"
    "                link = f\"{base}/api/notes?limit={limit}&before_id={data[-1]['id']}\"\n"
    "        except Exception as ex:\n"
    "            try:\n"
    "                current_app.logger.warning('fallback /api/notes (db issue): %r', ex)\n"
    "            except Exception:\n"
    "                pass\n"
    "        from flask import make_response\n"
    "        resp = jsonify(data)\n"
    "        resp.headers['Access-Control-Allow-Origin'] = '*'\n"
    "        if link:\n"
    "            resp.headers['Link'] = f\"<{link}>; rel=\\\"next\\\"\"\n"
    "        return resp, 200\n\n"
    "    # Registrar OPTIONS /api/notes si no existe\n"
    "    try:\n"
    "        exists_opt = any((r.rule=='/api/notes' and 'OPTIONS' in r.methods) for r in app.url_map.iter_rules())\n"
    "    except Exception:\n"
    "        exists_opt = False\n"
    "    if not exists_opt:\n"
    "        app.add_url_rule('/api/notes', 'api_notes_options_safe', _api_options_ok, methods=['OPTIONS'])\n"
    "    # Registrar GET /api/notes fallback SOLO si no existe\n"
    "    try:\n"
    "        exists_get = any((r.rule=='/api/notes' and 'GET' in r.methods) for r in app.url_map.iter_rules())\n"
    "    except Exception:\n"
    "        exists_get = False\n"
    "    if not exists_get:\n"
    "        app.add_url_rule('/api/notes', 'api_notes_fallback_safe', _api_notes_fallback, methods=['GET'])\n\n"
)

# Insertar antes de 'return app'
if "api_notes_fallback_safe" not in s:
    # buscamos el 'return app' más a la derecha
    m = list(re.finditer(r"^\s*return\s+app\s*$", s, flags=re.M))
    if m:
        i = m[-1].start()
        s = s[:i] + injection + s[i:]

if s != orig:
    io.open(p,"w",encoding="utf-8").write(s)
    print("[patch] backend/__init__.py actualizado")
else:
    print("[info] backend/__init__.py ya tenía los parches")
PY

# sanity
python -m py_compile backend/__init__.py && echo "py_compile OK"

echo "Listo. Ahora prueba:"
echo "  curl -i -X OPTIONS https://paste12-rmsk.onrender.com/api/notes"
echo "  curl -i https://paste12-rmsk.onrender.com/api/notes?limit=10 | head -n1"
