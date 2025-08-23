import os
from flask import Flask, jsonify

def _db_uri():
    uri = os.getenv("DATABASE_URL") or os.getenv("SQLALCHEMY_DATABASE_URI") or "sqlite:///data.db"
    # Render suele dar postgres://; SQLAlchemy moderno prefiere postgresql+psycopg2://
    if uri.startswith("postgres://"):
        uri = uri.replace("postgres://", "postgresql+psycopg2://", 1)
    return uri

app = Flask(__name__, static_folder=None)
app.config.update(
    SQLALCHEMY_DATABASE_URI=_db_uri(),
    SQLALCHEMY_TRACK_MODIFICATIONS=False,
    SECRET_KEY=os.getenv("SECRET_KEY", "dev"),
)

# 1) DB única del paquete backend
from backend import db  # instancia global única
db.init_app(app)

# 2) API real
try:
    from backend.routes import api as api_bp  # blueprint real
    app.register_blueprint(api_bp)
except Exception as e:
    @app.get("/__api_import_error")
    def __api_import_error():
        return jsonify({"ok": False, "where": "import backend.routes", "error": str(e)}), 500

# 3) Frontend
try:
    from backend.webui import ensure_webui
    ensure_webui(app)
except Exception:
    pass

# 4) Health & diag
@app.get("/api/health")
def _health():
    return jsonify({"ok": True, "note": "wsgiapp"}), 200

@app.get("/__whoami")
def __whoami():
    rules = [{"rule": r.rule, "methods": sorted(r.methods)} for r in app.url_map.iter_rules()]
    has_detail = any("/api/notes/<int:note_id>" == r["rule"] for r in rules)
    return jsonify({
        "blueprints": sorted(app.blueprints.keys()),
        "rules_count": len(rules),
        "has_detail_routes": has_detail,
        "sample": sorted(rules, key=lambda x: x["rule"])[:25],
    })
