import os
from flask import Flask, jsonify
from backend.force_api import install as _force_api_install


def _db_uri():
    # Render: DATABASE_URL o SQLALCHEMY_DATABASE_URI; si nada, sqlite
    uri = os.getenv("DATABASE_URL") or os.getenv("SQLALCHEMY_DATABASE_URI") or "sqlite:///data.db"
    # Normalizar a psycopg v3 (no psycopg2)
    if uri.startswith("postgres://"):
        uri = uri.replace("postgres://", "postgresql+psycopg://", 1)
    elif uri.startswith("postgresql://") and "+psycopg" not in uri and "+psycopg2" not in uri:
        uri = uri.replace("postgresql://", "postgresql+psycopg://", 1)
    return uri

app = Flask(__name__, static_folder=None)
app.config.update(
    SQLALCHEMY_DATABASE_URI=_db_uri(),
    SQLALCHEMY_TRACK_MODIFICATIONS=False,
    SECRET_KEY=os.getenv("SECRET_KEY", "dev"),
)

# DB única del paquete backend
from backend import db
db.init_app(app)

# API real
try:
    from backend.routes import api as api_bp
    app.register_blueprint(api_bp)
except Exception as e:
    import traceback
    _err_msg = f"{e.__class__.__name__}: {e}"
    _err_tb = traceback.format_exc()
    @app.get("/__api_import_error")
    def __api_import_error():
        return jsonify({"ok": False, "where": "import backend.routes", "error": _err_msg, "traceback": _err_tb}), 500

# Frontend
try:
    from backend.webui import ensure_webui
    ensure_webui(app)
except Exception:
    pass

# Health & diag
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


# --- WSGI FAILSAFE: instala /api/ping y /api/_routes si no están ---
try:
    _force_api_install(app)  # type: ignore[name-defined]
except Exception:
    pass
