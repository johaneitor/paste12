import os, sys
from importlib import import_module

def resolve_base_app():
    spec = os.environ.get("APP_MODULE", "app:app")
    if ":" in spec: mod_name, attr = spec.split(":", 1)
    else:           mod_name, attr = spec, None
    if os.getcwd() not in sys.path:
        sys.path.insert(0, os.getcwd())
    try:
        base_mod = import_module(mod_name)
    except ModuleNotFoundError as e:
        raise RuntimeError(f"No pude importar módulo '{mod_name}'. Ajusta APP_MODULE (p.ej. 'mi_pkg.app:app').") from e

    def getattr_safe(m, name): return getattr(m, name) if hasattr(m, name) else None

    if attr and attr.endswith("()"):
        fn = getattr_safe(base_mod, attr[:-2])
        if not callable(fn):
            raise RuntimeError(f"'{mod_name}:{attr}' no existe o no es callable.")
        return fn()
    if attr:
        obj = getattr_safe(base_mod, attr)
        if obj is None:
            raise RuntimeError(f"'{mod_name}:{attr}' no existe.")
        return obj
    obj = getattr_safe(base_mod, "app") or getattr_safe(base_mod, "application")
    if obj is not None: return obj
    for fn_name in ("create_app","make_app"):
        fn = getattr_safe(base_mod, fn_name)
        if callable(fn): return fn()
    raise RuntimeError(f"No encontré 'app', 'application' ni factoría en '{mod_name}'.")

base_app = resolve_base_app()

# ¿Flask o ASGI?
is_flask = False
try:
    from flask import Flask
    is_flask = isinstance(base_app, Flask)
except Exception:
    is_flask = False

if not is_flask:
    # ASGI → envolver a WSGI
    try:
        from asgiref.wsgi import AsgiToWsgi
        app = AsgiToWsgi(base_app)
    except Exception as e:
        raise RuntimeError("Detecté app ASGI, pero no pude envolverla a WSGI. Instala 'asgiref'.") from e
else:
    from flask import send_from_directory, Response
    try:
        from flask_cors import CORS
    except Exception:
        CORS = None

    app = base_app

    # Parche contra choque de blueprints duplicados (evita ValueError)
    _orig_reg = app.register_blueprint
    def _safe_register(bp, **options):
        name = options.get("name", getattr(bp, "name", None))
        if not name and hasattr(bp, "name"): name = bp.name
        if name and name in app.blueprints:
            # si ya está exactamente el mismo objeto, no registrar
            if app.blueprints[name] is bp:
                return
            # si hay colisión, renombrar con sufijo incremental
            base = name; i = 2
            while f"{base}_{i}" in app.blueprints:
                i += 1
            options["name"] = f"{base}_{i}"
        return _orig_reg(bp, **options)
    app.register_blueprint = _safe_register

    if CORS:
        CORS(app, resources={r"/api/*": {"origins": "*"}}, supports_credentials=False, max_age=86400)

    def _has_rule(rule):
        try: return any(r.rule == rule for r in app.url_map.iter_rules())
        except Exception: return False

    if not _has_rule("/"):
        @app.get("/")
        def _root():
            pub = os.path.join(os.getcwd(), "public")
            index = os.path.join(pub, "index.html")
            if os.path.isfile(index): return send_from_directory(pub, "index.html")
            return Response("<!doctype html><h1>OK</h1><p>Backend vivo.</p>", mimetype="text/html")

    # Interacciones: like/report (endpoint únicos)
    import sqlalchemy as sa
    def _engine():
        url = os.environ.get("SQLALCHEMY_DATABASE_URI") or os.environ.get("DATABASE_URL")
        if not url: raise RuntimeError("DATABASE_URL/SQLALCHEMY_DATABASE_URI no definido")
        return sa.create_engine(url, pool_pre_ping=True)

    def _ensure_interaction_endpoint(name, column):
        rule = f"/api/notes/<int:note_id>/{name}"
        endpoint = f"notes_{name}_handler"
        if _has_rule(rule) or endpoint in getattr(app, "view_functions", {}):
            return
        def handler(note_id):
            from flask import jsonify
            eng = _engine()
            with eng.begin() as cx:
                cx.execute(sa.text(f"UPDATE note SET {column} = COALESCE({column},0) + 1 WHERE id=:id"), {"id": note_id})
                row = cx.execute(sa.text("SELECT id, likes, reports, views FROM note WHERE id=:id"), {"id": note_id}).fetchone()
            if not row: return jsonify(ok=False, error="not_found"), 404
            return jsonify(ok=True, id=row.id, likes=row.likes, reports=row.reports, views=row.views)
        handler.__name__ = endpoint
        app.add_url_rule(rule, endpoint=endpoint, view_func=handler, methods=["POST"])

    _ensure_interaction_endpoint("like",   "likes")
    _ensure_interaction_endpoint("report", "reports")
