from app import app

if __name__ == "__main__":
    import os
    host = os.environ.get("HOST", "0.0.0.0")
    port = int(os.environ.get("PORT", "8000"))
    app.run(host=host, port=port)

# >>> interactions_module_autoreg
try:
    from flask import current_app as _cap
    _app = _cap._get_current_object() if _cap else app
except Exception:
    try:
        _app = app
    except Exception:
        _app = None

def _has_rule(app, path, method):
    try:
        for r in app.url_map.iter_rules():
            if str(r)==path and method.upper() in r.methods:
                return True
    except Exception:
        pass
    return False

try:
    if _app is not None:
        need_like = not _has_rule(_app, "/api/notes/<int:note_id>/like", "POST")
        need_view = not _has_rule(_app, "/api/notes/<int:note_id>/view", "POST")
        need_stats= not _has_rule(_app, "/api/notes/<int:note_id>/stats","GET")
        if need_like or need_view or need_stats:
            from backend.modules.interactions import interactions_bp
            _app.register_blueprint(interactions_bp, url_prefix="/api")
except Exception as e:
    # silent; no romper inicio de app
    pass
# <<< interactions_module_autoreg
