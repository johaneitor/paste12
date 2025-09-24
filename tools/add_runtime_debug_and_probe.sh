#!/usr/bin/env bash
set -Eeuo pipefail

echo "➤ Escribo backend/debug_runtime.py"
mkdir -p backend
cat > backend/debug_runtime.py <<'PY'
from flask import Blueprint, jsonify, current_app, request
from pathlib import Path
import sys, os

debug = Blueprint("debug", __name__)

@debug.get("/__debug/routes")
def dbg_routes():
    rules = [{
        "rule": r.rule,
        "methods": sorted(m for m in r.methods if m not in {"HEAD","OPTIONS"}),
        "endpoint": r.endpoint
    } for r in current_app.url_map.iter_rules()]
    # Intentar detectar FRONT_DIR del webui
    try:
        from backend.webui import FRONT_DIR as fd
        fd_str = str(fd)
        fd_exists = Path(fd).exists()
    except Exception:
        fd_str, fd_exists = None, False

    return jsonify({
        "python": sys.version,
        "cwd": os.getcwd(),
        "module_search_0": sys.path[:5],  # primeras entradas
        "uses_backend_entry": ("backend.entry" in sys.modules),
        "has_root_rule": any(r["rule"] == "/" for r in rules),
        "front_dir": fd_str,
        "front_dir_exists": fd_exists,
        "rules": sorted(rules, key=lambda x: x["rule"])[:200],
    }), 200

@debug.get("/__debug/fs")
def dbg_fs():
    p = Path(request.args.get("path","."))  # relativo al CWD del proceso
    info = {"path": str(p.resolve()), "exists": p.exists(), "is_dir": p.is_dir()}
    if p.exists() and p.is_dir():
        try:
            info["list"] = sorted(os.listdir(p))[:200]
        except Exception as e:
            info["list_error"] = str(e)
    return jsonify(info), 200
PY

echo "➤ Parchar backend/entry.py para registrar el debug siempre"
# Inserta el registro del blueprint de debug sin romper nada
python - <<'PY'
from pathlib import Path, re
p = Path("backend/entry.py")
s = p.read_text(encoding="utf-8")

inject = """
# --- registrar blueprint de debug (no crítico si falla) ---
try:
    from backend.debug_runtime import debug as _debug_bp  # type: ignore
    app.register_blueprint(_debug_bp)  # type: ignore[attr-defined]
except Exception:
    pass
""".strip("\n")

# Evitar duplicados si ya está
if "backend.debug_runtime" not in s:
    # Pegarlo al final del archivo, que ya construye 'app'
    if not s.endswith("\n"):
        s += "\n"
    s += "\n" + inject + "\n"
    p.write_text(s, encoding="utf-8")
    print("entry.py: debug blueprint agregado.")
else:
    print("entry.py: ya tenía debug (ok).")
PY

echo "➤ Commit & push"
git add backend/debug_runtime.py backend/entry.py
git commit -m "feat(debug): blueprint __debug/* con rutas/FS y registro desde backend.entry"
git push origin main

cat > tools/probe_render_debug.sh <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
echo "BASE = $BASE"
echo
echo "--- __debug/routes ---"
curl -sS "$BASE/__debug/routes" | python -m json.tool | sed -n '1,120p' || true
echo
echo "--- __debug/fs?path=. ---"
curl -sS "$BASE/__debug/fs?path=." | python -m json.tool || true
echo
echo "--- __debug/fs?path=backend ---"
curl -sS "$BASE/__debug/fs?path=backend" | python -m json.tool || true
echo
echo "--- __debug/fs?path=backend/frontend ---"
curl -sS "$BASE/__debug/fs?path=backend/frontend" | python -m json.tool || true
SH
chmod +x tools/probe_render_debug.sh

echo "✓ Listo. Tras el deploy, ejecutá: tools/probe_render_debug.sh 'https://paste12-rmsk.onrender.com'"
