import os, sys, json
from importlib import import_module

def resolve_base_app():
    spec = os.environ.get("APP_MODULE", "app:app")
    if ":" in spec:
        mod_name, attr = spec.split(":", 1)
    else:
        mod_name, attr = spec, None

    if os.getcwd() not in sys.path:
        sys.path.insert(0, os.getcwd())

    try:
        base_mod = import_module(mod_name)
    except ModuleNotFoundError as e:
        raise RuntimeError(f"No pude importar módulo '{mod_name}'. Ajusta APP_MODULE (p.ej. 'mi_pkg.app:app').") from e

    def getattr_safe(m, name):
        return getattr(m, name) if hasattr(m, name) else None

    # APP_MODULE con factoría "create_app()" o "make_app()"
    if attr and attr.endswith("()"):
        func_name = attr[:-2]
        factory = getattr_safe(base_mod, func_name)
        if not callable(factory):
            raise RuntimeError(f"'{mod_name}:{func_name}()' no existe o no es callable.")
        return factory()

    # APP_MODULE con atributo explícito
    if attr:
        obj = getattr_safe(base_mod, attr)
        if obj is None:
            raise RuntimeError(f"'{mod_name}:{attr}' no existe.")
        return obj

    # Autointento: app -> application -> create_app()/make_app()
    obj = getattr_safe(base_mod, "app") or getattr_safe(base_mod, "application")
    if obj is not None:
        return obj
    for fn in ("create_app", "make_app"):
        f = getattr_safe(base_mod, fn)
        if callable(f):
            return f()
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
    # ---- ASGI → envolver a WSGI y añadir interceptor para rutas auxiliares ----
    try:
        from asgiref.wsgi import AsgiToWsgi
        base_wsgi = AsgiToWsgi(base_app)
    except Exception as e:
        raise RuntimeError("Detecté app ASGI, pero no pude envolverla a WSGI. Instala 'asgiref'.") from e

    # Utilidades
    import sqlalchemy as sa
    from werkzeug.wrappers import Request, Response as WResponse

    def _engine():
        url = os.environ.get("SQLALCHEMY_DATABASE_URI") or os.environ.get("DATABASE_URL")
        if not url:
            raise RuntimeError("DATABASE_URL/SQLALCHEMY_DATABASE_URI no definido")
        return sa.create_engine(url, pool_pre_ping=True)

    def _json(status_code: int, data: dict):
        body = json.dumps(data, default=str).encode("utf-8")
        return f"{status_code} " + ("OK" if status_code == 200 else "ERROR"), [
            ("Content-Type", "application/json; charset=utf-8"),
            ("Content-Length", str(len(body))),
        ], body

    @Request.application
    def _shim(request):
        path = request.path
        method = request.method.upper()

        # /api/deploy-stamp
        if path == "/api/deploy-stamp" and method == "GET":
            data = dict(
                ok=True,
                commit=os.environ.get("RENDER_GIT_COMMIT") or os.environ.get("COMMIT") or "",
                stamp=os.environ.get("DEPLOY_STAMP") or "",
            )
            status, headers, body = _json(200, data)
            return WResponse(body, status=status, headers=headers)

        # /api/notes_fallback
        if path == "/api/notes_fallback" and method == "GET":
            try:
                limit = int(request.args.get("limit", 20))
                limit = max(1, min(limit, 100))
            except Exception:
                limit = 20
            cursor_ts = request.args.get("cursor_ts")
            cursor_id = request.args.get("cursor_id", type=int)

            eng = _engine()
            with eng.begin() as cx:
                if cursor_ts and cursor_id:
                    q = sa.text("""
                        SELECT id, title, url, summary, content, timestamp, likes, views, reports
                        FROM note
                        WHERE (timestamp < :ts) OR (timestamp = :ts AND id < :id)
                        ORDER BY timestamp DESC, id DESC
                        LIMIT :lim
                    """)
                    rows = cx.execute(q, {"ts": cursor_ts, "id": cursor_id, "lim": limit}).mappings().all()
                else:
                    q = sa.text("""
                        SELECT id, title, url, summary, content, timestamp, likes, views, reports
                        FROM note
                        ORDER BY timestamp DESC, id DESC
                        LIMIT :lim
                    """)
                    rows = cx.execute(q, {"lim": limit}).mappings().all()
            items = [dict(r) for r in rows]
            next_cursor = None
            if items:
                last = items[-1]
                next_cursor = {"cursor_ts": str(last["timestamp"]), "cursor_id": last["id"]}
            status, headers, body = _json(200, {"ok": True, "items": items, "next": next_cursor})
            return WResponse(body, status=status, headers=headers)

        # /api/notes_diag
        if path == "/api/notes_diag" and method == "GET":
            eng = _engine()
            with eng.begin() as cx:
                dialect = cx.connection.engine.dialect.name
                if dialect.startswith("sqlite"):
                    cols = [dict(row) for row in cx.execute(sa.text("PRAGMA table_info(note)")).mappings().all()]
                else:
                    cols = [dict(row) for row in cx.execute(sa.text("""
                        SELECT column_name, data_type
                        FROM information_schema.columns
                        WHERE table_name = 'note'
                        ORDER BY ordinal_position
                    """)).mappings().all()]
            status, headers, body = _json(200, {"ok": True, "dialect": dialect, "columns": cols})
            return WResponse(body, status=status, headers=headers)

        # Para todo lo demás, despacha a la app original
        return base_wsgi

    # El WSGI final es el *dispatcher* (shim primero, base si no coincide ruta)
    def app(environ, start_response):
        # _shim devuelve WResponse ó base_wsgi (callable WSGI)
        res = _shim(environ, start_response)
        if callable(res):
            return res(environ, start_response)
        return res(environ, start_response)

else:
    # ---- FLASK → inyectar rutas y CORS como antes ----
    from flask import request, jsonify, send_from_directory, Response
    try:
        from flask_cors import CORS
    except Exception:
        CORS = None

    app = base_app

    if CORS:
        CORS(app, resources={r"/api/*": {"origins": "*"}}, supports_credentials=False, max_age=86400)

    def _has_rule(rule):
        try:
            return any(r.rule == rule for r in app.url_map.iter_rules())
        except Exception:
            return False

    if not _has_rule("/"):
        @app.get("/")
        def _root():
            pub = os.path.join(os.getcwd(), "public")
            index = os.path.join(pub, "index.html")
            if os.path.isfile(index):
                return send_from_directory(pub, "index.html")
            return Response("<!doctype html><h1>OK</h1><p>Backend vivo.</p>", mimetype="text/html")

    import sqlalchemy as sa
    def _engine():
        url = os.environ.get("SQLALCHEMY_DATABASE_URI") or os.environ.get("DATABASE_URL")
        if not url:
            raise RuntimeError("DATABASE_URL/SQLALCHEMY_DATABASE_URI no definido")
        return sa.create_engine(url, pool_pre_ping=True)

    def _ensure_interaction_endpoint(name, column):
        rule = f"/api/notes/<int:note_id>/{name}"
        endpoint = f"notes_{name}_handler"
        if _has_rule(rule) or endpoint in getattr(app, "view_functions", {}):
            return
        def handler(note_id):
            eng = _engine()
            with eng.begin() as cx:
                cx.execute(sa.text(f"UPDATE note SET {column} = COALESCE({column},0) + 1 WHERE id=:id"), {"id": note_id})
                row = cx.execute(sa.text("SELECT id, likes, reports, views FROM note WHERE id=:id"), {"id": note_id}).fetchone()
            if not row:
                return jsonify(ok=False, error="not_found"), 404
            return jsonify(ok=True, id=row.id, likes=row.likes, reports=row.reports, views=row.views)
        handler.__name__ = endpoint
        app.add_url_rule(rule, endpoint=endpoint, view_func=handler, methods=["POST"])

    _ensure_interaction_endpoint("like",   "likes")
    _ensure_interaction_endpoint("report", "reports")

    @app.get("/api/deploy-stamp")
    def _deploy_stamp():
        return jsonify(
            ok=True,
            commit=os.environ.get("RENDER_GIT_COMMIT") or os.environ.get("COMMIT") or "",
            stamp=os.environ.get("DEPLOY_STAMP") or ""
        ), 200

    @app.get("/api/notes_fallback")
    def _notes_fallback():
        try:
            limit = int(request.args.get("limit", 20))
            limit = max(1, min(limit, 100))
        except Exception:
            limit = 20
        cursor_ts = request.args.get("cursor_ts")
        cursor_id = request.args.get("cursor_id", type=int)

        eng = _engine()
        import sqlalchemy as sa
        with eng.begin() as cx:
            if cursor_ts and cursor_id:
                q = sa.text("""
                    SELECT id, title, url, summary, content, timestamp, likes, views, reports
                    FROM note
                    WHERE (timestamp < :ts) OR (timestamp = :ts AND id < :id)
                    ORDER BY timestamp DESC, id DESC
                    LIMIT :lim
                """)
                rows = cx.execute(q, {"ts": cursor_ts, "id": cursor_id, "lim": limit}).mappings().all()
            else:
                q = sa.text("""
                    SELECT id, title, url, summary, content, timestamp, likes, views, reports
                    FROM note
                    ORDER BY timestamp DESC, id DESC
                    LIMIT :lim
                """)
                rows = cx.execute(q, {"lim": limit}).mappings().all()
        items = [dict(r) for r in rows]
        next_cursor = None
        if items:
            last = items[-1]
            next_cursor = {"cursor_ts": str(last["timestamp"]), "cursor_id": last["id"]}
        return jsonify(ok=True, items=items, next=next_cursor)

    @app.get("/api/notes_diag")
    def _notes_diag():
        eng = _engine()
        import sqlalchemy as sa
        with eng.begin() as cx:
            dialect = cx.connection.engine.dialect.name
            if dialect.startswith("sqlite"):
                cols = [dict(row) for row in cx.execute(sa.text("PRAGMA table_info(note)")).mappings().all()]
            else:
                cols = [dict(row) for row in cx.execute(sa.text("""
                    SELECT column_name, data_type
                    FROM information_schema.columns
                    WHERE table_name = 'note'
                    ORDER BY ordinal_position
                """)).mappings().all()]
        return jsonify(ok=True, dialect=dialect, columns=cols), 200
