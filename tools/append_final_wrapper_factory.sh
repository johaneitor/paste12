#!/usr/bin/env bash
set -euo pipefail
f="backend/__init__.py"
[[ -f "$f" ]] || { echo "No existe $f"; exit 1; }

# Normalizar EOL/espacios por si hay tabs viejos que disparan IndentationError
python - <<'PY'
from pathlib import Path
p = Path("backend/__init__.py")
src = p.read_text(encoding="utf-8").replace("\r\n","\n").replace("\r","\n").replace("\t","    ")
p.write_text(src, encoding="utf-8")
print("OK: __init__.py normalizado (EOL + tabs→spaces)")
PY

# Añadir el wrapper final idempotente
python - <<'PY'
from pathlib import Path, re
p = Path("backend/__init__.py")
s = p.read_text(encoding="utf-8")

block = r'''
# === FINAL_FACTORY_WRAPPER (idempotente) ===
try:
    _orig_create_app
except NameError:
    _orig_create_app = create_app  # type: ignore

def create_app(*args, **kwargs):  # type: ignore[no-redef]
    app = _orig_create_app(*args, **kwargs)

    # Registrar API blueprint bajo /api (idempotente)
    try:
        from backend.routes import api as api_bp
        # Si no hay endpoint que empiece con "api." o regla que empiece con "/api/", registramos
        rules = list(app.url_map.iter_rules())
        have_api_pref = any(str(r).startswith("/api/") for r in rules)
        if not have_api_pref:
            app.register_blueprint(api_bp, url_prefix="/api")
    except Exception:
        pass

    # Rutas failsafe a nivel app (por si el blueprint no aportó ping/_routes)
    try:
        from flask import jsonify as _j
        if not any(str(r).rstrip("/") == "/api/ping" for r in app.url_map.iter_rules()):
            app.add_url_rule("/api/ping", endpoint="api_ping_app", view_func=(lambda: _j({"ok": True, "pong": True, "src":"factory"})), methods=["GET"])
        if not any(str(r).rstrip("/") == "/api/_routes" for r in app.url_map.iter_rules()):
            def _dump():
                info=[]
                for r in app.url_map.iter_rules():
                    info.append({
                        "rule": str(r),
                        "methods": sorted(m for m in r.methods if m not in ("HEAD","OPTIONS")),
                        "endpoint": r.endpoint,
                    })
                info.sort(key=lambda x: x["rule"])
                return _j({"routes": info}), 200
            app.add_url_rule("/api/_routes", endpoint="api_routes_dump_app", view_func=_dump, methods=["GET"])
    except Exception:
        pass

    return app
'''

if "FINAL_FACTORY_WRAPPER" not in s:
    s = s.rstrip()+"\n\n"+block.lstrip("\n")
    Path("backend/__init__.py").write_text(s, encoding="utf-8")
    print("OK: FINAL_FACTORY_WRAPPER añadido")
else:
    print("Ya existía FINAL_FACTORY_WRAPPER (sin cambios)")
PY

git add backend/__init__.py >/dev/null 2>&1 || true
git commit -m "factory: añade wrapper FINAL idempotente, normaliza indent y fuerza /api ping/_routes" >/dev/null 2>&1 || true
git push origin HEAD >/dev/null 2>&1 || true
echo "✓ Commit & push hechos (factory)."
