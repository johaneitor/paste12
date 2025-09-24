#!/usr/bin/env bash
set -euo pipefail
TS="$(date -u +%Y%m%d-%H%M%SZ)"

# --- safety backups
[[ -f backend/routes.py ]] && cp -f backend/routes.py "backend/routes.py.$TS.bak" || true
[[ -f backend/__init__.py ]] && cp -f backend/__init__.py "backend/__init__.py.$TS.bak" || true

python - <<'PY'
import io, os, re

# 1) compat /api/notes/  ->  /api/notes  (307 preserva POST)
p = "backend/routes.py"
if os.path.exists(p):
    s = io.open(p, "r", encoding="utf-8").read()
    orig = s
    if "def _notes_slash_compat(" not in s:
        s += """

# --- compat: evitar 405 por trailing slash en /api/notes/
try:
    from flask import Blueprint, redirect, request
    from flask import current_app as _cur
    bp  # noqa: F401
except Exception:
    pass
else:
    @bp.route("/api/notes/", methods=["GET","POST","OPTIONS"], strict_slashes=False)
    def _notes_slash_compat():
        # 307 mantiene método y body para POST
        return redirect("/api/notes", code=307)
"""
    # 2) añadir after_request no-cache para HTML servida por Flask
    if "def _add_nocache_headers(" not in s:
        s += """

# --- no-cache en HTML para evitar servir versiones viejas
try:
    from flask import after_this_request
    from flask import current_app as _cur
except Exception:
    pass
else:
    try:
        @bp.after_request
        def _add_nocache_headers(resp):
            ct = resp.headers.get("Content-Type","")
            if ct.startswith("text/html"):
                resp.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
                resp.headers["Pragma"] = "no-cache"
            return resp
    except Exception:
        pass
"""
    if s != orig:
        io.open(p, "w", encoding="utf-8").write(s)
        print("[routes] compat 405 + no-cache añadidos")
    else:
        print("[routes] ya estaba OK")
else:
    print("[routes] backend/routes.py no existe (omitido)")

# 3) en __init__.py: asegurar TRACK_MODS y engine opts básicos (sin tocar lógica)
q = "backend/__init__.py"
if os.path.exists(q):
    s = io.open(q, "r", encoding="utf-8").read()
    orig = s
    s = s.replace("\t", "    ")  # normalizar tabs
    if "SQLALCHEMY_TRACK_MODIFICATIONS" not in s:
        s = re.sub(r"(app\\.config\\[\"SQLALCHEMY_DATABASE_URI\"].*?\\n)",
                   r"\\1    app.config[\"SQLALCHEMY_TRACK_MODIFICATIONS\"] = False\n", s, flags=re.S)
    if "SQLALCHEMY_ENGINE_OPTIONS" not in s:
        s = re.sub(r"(app\\.config\\[\"SQLALCHEMY_TRACK_MODIFICATIONS\"].*?\\n)",
                   r"\\1    app.config.setdefault(\"SQLALCHEMY_ENGINE_OPTIONS\", {\"pool_pre_ping\": True, \"pool_recycle\": 300})\n",
                   s, flags=re.S)
    if s != orig:
        io.open(q, "w", encoding="utf-8").write(s)
        print("[init] saneamiento mínimo aplicado")
    else:
        print("[init] ya estaba OK")
else:
    print("[init] backend/__init__.py no existe (omitido)")
PY

# 4) compilar rápido para detectar indent/syntax
python - <<'PY'
import py_compile, sys
for f in ("backend/__init__.py","backend/routes.py","contract_shim.py","wsgi.py"):
    try:
        py_compile.compile(f, doraise=True)
        print(f"✓ py_compile {f} OK")
    except Exception as e:
        print(f"✗ py_compile {f} FAIL -> {e}")
        sys.exit(1)
PY
echo "Listo. Despliega y probamos."
