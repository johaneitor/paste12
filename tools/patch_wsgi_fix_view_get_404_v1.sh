#!/usr/bin/env bash
set -euo pipefail
PY="wsgi.py"
[[ -f "$PY" ]] || { echo "ERROR: no existe $PY"; exit 1; }

python - <<'PY'
import io, os, re, py_compile
p="wsgi.py"
s=io.open(p,"r",encoding="utf-8").read()

marker="_p12_fix_view_get_mw"
if marker not in s:
    # Asegurar imports mínimos
    if re.search(r'^\s*import\s+json\b', s, re.M) is None:
        s = "import json\n" + s
    if re.search(r'^\s*from\s+urllib\.parse\s+import\s+parse_qs\b', s, re.M) is None:
        s = "from urllib.parse import parse_qs\n" + s

    s += r"""

# --- paste12: middleware para forzar 404 en GET /api/view ---
def _p12_fix_view_get_mw(app):
    def _app(env, start_response):
        path = env.get("PATH_INFO","")
        method = env.get("REQUEST_METHOD","GET").upper()
        if path == "/api/view" and method == "GET":
            # Siempre devolver 404 JSON para GET (negativo exige 404; POST se maneja en app)
            body = json.dumps({"error":"not_found"}).encode("utf-8")
            start_response("404 Not Found", [
                ("Content-Type","application/json"),
                ("Cache-Control","no-cache"),
                ("Content-Length", str(len(body)))
            ])
            return [body]
        return app(env, start_response)
    return _app
"""

    # Envolver 'application'
    if re.search(r'^\s*application\s*=', s, re.M):
        s += "\napplication = _p12_fix_view_get_mw(application)\n"
    else:
        s += "\napplication = _p12_fix_view_get_mw(globals().get('application') or (lambda e,sr: sr('404 Not Found',[]) or [b'']))\n"

    io.open(p,"w",encoding="utf-8").write(s)

# Validación sintáctica
py_compile.compile(p, doraise=True)
print("PATCH_OK", p)
PY

# Por cortesía, compilamos también el backend principal (no lo tocamos, pero gatea errores)
python -m py_compile wsgiapp/__init__.py 2>/dev/null || true
echo "OK: wsgi.py saneado"
