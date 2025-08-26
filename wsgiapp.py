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


# --- WSGI EARLY PIN: rutas mínimas para diagnóstico ---
try:
    from flask import jsonify as _j

    # __version: intento de short SHA
    try:
        import subprocess
        _rev = subprocess.check_output(["git","rev-parse","--short","HEAD"], text=True).strip()
    except Exception:
        _rev = None
    if not any(str(r).rstrip("/") == "/__version" for r in app.url_map.iter_rules()):
        @app.get("/__version")
        def __version():
            return _j({"rev": _rev}), 200

    # /api/ping
    if not any(str(r).rstrip("/") == "/api/ping" for r in app.url_map.iter_rules()):
        @app.get("/api/ping")
        def __ping_wsgi_early():
            return _j({"ok": True, "pong": True, "src": "wsgi-early"}), 200

    # /api/_routes
    if not any(str(r).rstrip("/") == "/api/_routes" for r in app.url_map.iter_rules()):
        @app.get("/api/_routes")
        def __routes_wsgi_early():
            info=[]
            for r in app.url_map.iter_rules():
                info.append({
                    "rule": str(r),
                    "methods": sorted(m for m in r.methods if m not in ("HEAD","OPTIONS")),
                    "endpoint": r.endpoint,
                })
            info.sort(key=lambda x: x["rule"])
            return _j({"routes": info}), 200
except Exception:
    # No rompemos wsgi aunque falle este bloque
    pass
# --- /WSGI EARLY PIN ---

# DB única del paquete backend
from backend import db
db.init_app(app)

# API real
try:
    from backend.routes import api as api_bp
    app.register_blueprint(api_bp, url_prefix="/api")
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


# --- WSGI_LOCAL_PING_ROUTES (idempotente) ---
try:
    from flask import jsonify as _j
    def _dump_routes_app(app):
        info=[]
        for r in app.url_map.iter_rules():
            info.append({"rule": str(r),
                         "methods": sorted(m for m in r.methods if m not in ("HEAD","OPTIONS")),
                         "endpoint": r.endpoint})
        info.sort(key=lambda x: x["rule"])
        return _j({"routes": info}), 200
    if not any(str(r).rstrip("/") == "/api/ping" for r in app.url_map.iter_rules()):
        app.add_url_rule("/api/ping", endpoint="api_ping_wsgi_local",
                         view_func=(lambda: _j({"ok": True, "pong": True, "src": "wsgi-local"})),
                         methods=["GET"])
    if not any(str(r).rstrip("/") == "/api/_routes" for r in app.url_map.iter_rules()):
        app.add_url_rule("/api/_routes", endpoint="api_routes_dump_wsgi_local",
                         view_func=(lambda: _dump_routes_app(app)), methods=["GET"])
except Exception:
    pass


# --- WSGI DIRECT API ENDPOINTS (decorators, no blueprints) ---
from flask import jsonify as _jsonify
@app.get("/api/ping")
def _api_ping():
    return _jsonify({"ok": True, "pong": True, "src": "wsgiapp"}), 200

@app.get("/api/_routes")
def _api_routes_dump():
    info=[]
    for r in app.url_map.iter_rules():
        info.append({
            "rule": str(r),
            "methods": sorted(m for m in r.methods if m not in ("HEAD","OPTIONS")),
            "endpoint": r.endpoint
        })
    info.sort(key=lambda x: x["rule"])
    return _jsonify({"routes": info}), 200



# --- WSGI FORCE NOW: endpoints directos y versión ---
try:
    from flask import jsonify as _j
    with app.app_context():
        # /__version
        try:
            import subprocess, os
            _git_rev = subprocess.check_output(["git","rev-parse","--short","HEAD"], text=True).strip()
        except Exception:
            _git_rev = None
        @app.get("/__version")
        def __version():
            return _j({"rev": _git_rev}), 200

        # /api/ping directo
        try:
            if not any(str(r).rstrip("/") == "/api/ping" for r in app.url_map.iter_rules()):
                app.add_url_rule("/api/ping",
                                 endpoint="api_ping_force_now",
                                 view_func=(lambda: _j({"ok": True, "pong": True, "src": "wsgi-force-now"})),
                                 methods=["GET"])
        except Exception:
            pass

        # /api/_routes directo
        try:
            if not any(str(r).rstrip("/") == "/api/_routes" for r in app.url_map.iter_rules()):
                def _dump_routes_force():
                    info=[]
                    for r in app.url_map.iter_rules():
                        info.append({
                            "rule": str(r),
                            "methods": sorted(m for m in r.methods if m not in ("HEAD","OPTIONS")),
                            "endpoint": r.endpoint
                        })
                    info.sort(key=lambda x: x["rule"])
                    return _j({"routes": info}), 200
                app.add_url_rule("/api/_routes",
                                 endpoint="api_routes_dump_force_now",
                                 view_func=_dump_routes_force,
                                 methods=["GET"])
        except Exception:
            pass
except Exception:
    # no rompemos wsgi aunque falle algo
    pass



# --- WSGI DIRECT API ENDPOINTS (decorators, no blueprints) ---
try:
    from flask import jsonify as _jsonify
    @app.get("/api/ping")
    def _api_ping():
        return _jsonify({"ok": True, "pong": True, "src": "wsgiapp"}), 200

    @app.get("/api/_routes")
    def _api_routes_dump():
        info=[]
        for r in app.url_map.iter_rules():
            info.append({
                "rule": str(r),
                "methods": sorted(m for m in r.methods if m not in ("HEAD","OPTIONS")),
                "endpoint": r.endpoint
            })
        info.sort(key=lambda x: x["rule"])
        return _jsonify({"routes": info}), 200
except Exception:
    pass
