from flask import Blueprint, jsonify, current_app
debug_api = Blueprint("debug_api", __name__)

@debug_api.get("/api/_routes")
def list_routes():
    app = current_app
    info = []
    for rule in app.url_map.iter_rules():
        info.append({
            "rule": str(rule),
            "methods": sorted([m for m in rule.methods if m not in ("HEAD", "OPTIONS")]),
            "endpoint": rule.endpoint,
        })
    return jsonify({"routes": sorted(info, key=lambda r: r["rule"])}), 200
