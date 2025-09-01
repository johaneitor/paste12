import os, sys, json
from importlib import import_module

# Asegura que el directorio del archivo (repo) esté en sys.path
_REPO_DIR = os.path.dirname(os.path.abspath(__file__))
if _REPO_DIR not in sys.path:
    sys.path.insert(0, _REPO_DIR)

def resolve_base_app():
    spec = os.environ.get("APP_MODULE", "app:app")
    if ":" in spec:
        mod_name, attr = spec.split(":", 1)
    else:
        mod_name, attr = spec, None

    try:
        base_mod = import_module(mod_name)
    except ModuleNotFoundError as e:
        raise RuntimeError(f"No pude importar módulo '{mod_name}'. Ajusta APP_MODULE (p.ej. 'mi_pkg.app:app').") from e

    def getattr_safe(m, name):
        return getattr(m, name) if hasattr(m, name) else None

    if attr and attr.endswith("()"):
        func_name = attr[:-2]
        factory = getattr_safe(base_mod, func_name)
        if not callable(factory):
            raise RuntimeError(f"'{mod_name}:{func_name}()' no existe o no es callable.")
        return factory()

    if attr:
        obj = getattr_safe(base_mod, attr)
        if obj is None:
            raise RuntimeError(f"'{mod_name}:{attr}' no existe.")
        return obj

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
    # ---------- ASGI → WSGI ----------
    from asgiref.wsgi import AsgiToWsgi
    app = AsgiToWsgi(base_app)
else:
    # ---------- FLASK ----------
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
