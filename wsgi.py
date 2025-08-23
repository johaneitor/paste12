from backend.entry import app
import sys

@app.get("/__whoami")
def __whoami():
    info = {"blueprints": list(app.blueprints.keys())}
    rules = sorted([r.rule for r in app.url_map.iter_rules()])
    info["routes_sample"] = rules[:40]
    info["has_detail_routes"] = any(r.startswith("/api/notes/<") for r in rules)
    info["uses_backend_entry"] = "backend.entry" in sys.modules
    try:
        import backend.routes as R  # noqa: F401
        info["routes_import_ok"] = True
    except Exception as e:
        info["routes_import_ok"] = False
        info["routes_import_err"] = str(e)
    return info
