from backend.entry import app
import sys

@app.get("/__whoami")
def __whoami():
    rules = sorted([r.rule for r in app.url_map.iter_rules()])
    return {
        "blueprints": list(app.blueprints.keys()),
        "routes_sample": rules[:60],
        "has_detail_routes": any(r.startswith("/api/notes/<") for r in rules),
        "uses_backend_entry": "backend.entry" in sys.modules,
    }
