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
