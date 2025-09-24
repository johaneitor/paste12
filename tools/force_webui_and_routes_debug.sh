#!/usr/bin/env bash
set -Eeuo pipefail

INIT="backend/__init__.py"
WEBUI="backend/webui.py"

echo "➤ Backups"
cp -f "$INIT" "$INIT.bak.$(date +%s)"  2>/dev/null || true
cp -f "$WEBUI" "$WEBUI.bak.$(date +%s)" 2>/dev/null || true

echo "➤ Asegurar blueprint webui robusto (sirve /, /js/*, /css/*, robots)"
python - <<'PY'
from pathlib import Path
p = Path("backend/webui.py")
p.write_text("""\
from flask import Blueprint, send_from_directory
from pathlib import Path

PKG = Path(__file__).resolve().parent
CANDS = [PKG/'frontend', PKG.parent/'frontend', Path.cwd()/'frontend']
for c in CANDS:
    if c.exists():
        FRONT_DIR = c
        break
else:
    FRONT_DIR = CANDS[0]

webui = Blueprint("webui", __name__)

@webui.route("/", methods=["GET"])
def index():
    return send_from_directory(FRONT_DIR, "index.html")

@webui.route("/js/<path:fname>", methods=["GET"])
def js(fname):
    return send_from_directory(FRONT_DIR / "js", fname)

@webui.route("/css/<path:fname>", methods=["GET"])
def css(fname):
    return send_from_directory(FRONT_DIR / "css", fname)

@webui.route("/robots.txt", methods=["GET"])
def robots():
    return send_from_directory(FRONT_DIR, "robots.txt")

@webui.route("/favicon.ico", methods=["GET"])
def favicon():
    p = FRONT_DIR / "favicon.ico"
    if p.exists():
        return send_from_directory(FRONT_DIR, "favicon.ico")
    return ("", 204)
""", encoding="utf-8")
print("webui.py OK")
PY

echo "➤ Inyectar registro dentro de create_app() y ensure + /api/_routes"
python - <<'PY'
from pathlib import Path, re
initp = Path("backend/__init__.py")
s = initp.read_text(encoding="utf-8")

# ---- 1) Registrar dentro de create_app(...) antes de 'return app'
m = re.search(r'(def\s+create_app\s*\([^)]*\)\s*:\s*[\s\S]*?)\n(\s*)return\s+app\b', s)
if m:
    indent = m.group(2)
    block = f"""{indent}# -- register webui blueprint (forced) --
{indent}try:
{indent}    from .webui import webui
{indent}    app.register_blueprint(webui)
{indent}except Exception:
{indent}    pass
"""
    s = s[:m.start(2)] + block + s[m.start(2):]
    changed = True
else:
    changed = False

# ---- 2) Añadir helper ensure_webui(app) y endpoint /api/_routes
if "def ensure_webui(" not in s or "/api/_routes" not in s:
    extra = """
def ensure_webui(app):
    try:
        # Si no hay ruta '/', registramos el blueprint aquí también.
        if not any(getattr(r, "rule", None) == "/" for r in app.url_map.iter_rules()):
            from .webui import webui
            app.register_blueprint(webui)
    except Exception:
        pass

# Endpoint de diagnóstico: lista reglas (para verificar en Render)
try:
    @app.route("/api/_routes", methods=["GET"])
    def _routes_dump():
        try:
            rules = []
            for r in app.url_map.iter_rules():
                rules.append({
                    "rule": r.rule,
                    "methods": sorted(m for m in (r.methods or []) if m not in ("HEAD","OPTIONS")),
                    "endpoint": r.endpoint,
                })
            return {"routes": sorted(rules, key=lambda x: x["rule"])}, 200
        except Exception as e:
            return {"error":"routes_dump_failed","detail":str(e)}, 500
except Exception:
    # Si aún no existe 'app' (p.ej. si create_app no fue llamado), lo exponemos abajo.
    pass
"""
    s = s.rstrip() + "\n\n" + extra
    changed = True or changed

# ---- 3) Exponer 'app = create_app()' y llamar a ensure_webui(app)
if not re.search(r'^\s*app\s*=\s*create_app\(', s, re.M):
    s = s.rstrip() + "\n\n# WSGI export and ensure webui\napp = create_app()\nensure_webui(app)\n"
    changed = True
else:
    # si ya existe, asegurar ensure_webui(app) al final
    if "ensure_webui(app)" not in s:
        s = s.rstrip() + "\nensure_webui(app)\n"
        changed = True

if changed:
    initp.write_text(s, encoding="utf-8")
    print("__init__.py actualizado")
else:
    print("__init__.py ya estaba correcto")
PY

echo "➤ Commit & push"
git add backend/__init__.py backend/webui.py || true
git commit -m "fix(web): forzar registro de webui (en create_app y ensure) + endpoint /api/_routes; exponer app=create_app()" || true
git push origin main

echo "✓ Hecho."
