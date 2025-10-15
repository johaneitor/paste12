from __future__ import annotations
import os
from flask import Flask, jsonify
from backend import create_app, db

VER = "triplex-v2"

def _has_rule(app, rule: str, method: str) -> bool:
    try:
        for r in app.url_map.iter_rules():
            if str(r) == rule and method.upper() in r.methods:
                return True
    except Exception:
        pass
    return False

app: Flask = create_app()

# Registrar /api/notes si faltara (idempotente)
try:
    from backend.routes_notes import register_api
    if not (_has_rule(app, "/api/notes", "GET") and _has_rule(app, "/api/notes", "POST")):
        register_api(app)
except Exception:
    pass

# Health con marca
if not _has_rule(app, "/api/health", "GET"):
    @app.get("/api/health")
    def _health():
        ok_api = _has_rule(app, "/api/notes", "GET") and _has_rule(app, "/api/notes", "POST")
        return jsonify(ok=True, note="triplex", ver=VER, api=ok_api)

# create_all no falla si ya existen tablas
try:
    with app.app_context():
        db.create_all()
except Exception:
    pass

if __name__ == "__main__":
    host = os.environ.get("HOST", "0.0.0.0")
    port = int(os.environ.get("PORT", "8000"))
    app.run(host=host, port=port)

# --- Root index pastel + no-store ---
try:
    from flask import send_from_directory, current_app, make_response, request

    # Reemplaza el root, o define uno si no existía
    @app.get("/")
    def root_index():
        """Serve frontend index with no-store, preferring backend/frontend."""
        # Preferir la vista canónica si existe (inyecta flags cuando hace falta)
        try:
            vf = current_app.view_functions.get("front_bp.index")
            if vf:
                resp = vf()
                try:
                    resp.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
                except Exception:
                    pass
                return resp
        except Exception:
            pass

        # Fallback: servir directamente desde backend/frontend; último recurso: static
        front_dir = None
        try:
            from backend.front_bp import FRONT_DIR as _FD  # type: ignore
            front_dir = _FD
        except Exception:
            front_dir = None

        try:
            dir_to_use = front_dir or os.path.join(os.getcwd(), "backend", "frontend")
            resp = make_response(send_from_directory(dir_to_use, "index.html"))
        except Exception:
            static_dir = (getattr(current_app, "static_folder", None)
                          or os.path.join(os.getcwd(), "backend", "static"))
            resp = make_response(send_from_directory(static_dir, "index.html"))

        # evita cache en la raíz
        try:
            resp.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
        except Exception:
            pass
        return resp

    # Cinturón y tirantes: si otra vista sirve '/', igual marcamos no-store
    @app.after_request
    def _no_store_root(resp):
        try:
            if request.path in ("/", "/index.html"):
                # si ya trae Cache-Control, lo reemplazamos por no-store
                resp.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
        except Exception:
            pass
        return resp
except Exception as _e:
    print("[app] Nota: no pude instalar root_index/no-store:", _e)

# --- Root index pastel + no-store (idempotente) ---
try:
    import os
    from flask import send_from_directory, current_app, make_response, request

    def _resolve_front_dir():
        """Resolve preferred frontend directory (backend/frontend), with fallbacks."""
        # Canonical FRONT_DIR si está disponible
        try:
            from backend.front_bp import FRONT_DIR as _FD  # type: ignore
            if os.path.isfile(os.path.join(_FD, "index.html")):
                return _FD
        except Exception:
            pass
        # Fallback al path del repo
        cand = os.path.join(os.getcwd(), "backend", "frontend")
        if os.path.isfile(os.path.join(cand, "index.html")):
            return cand
        # Último recurso: static_folder (podría no tener index.html)
        return getattr(current_app, "static_folder", None) or os.path.join(os.getcwd(), "backend", "static")

    @app.after_request
    def _no_store_root(resp):
        try:
            # sólo en raíz y /index.html evitamos cache
            if request.path in ("/", "/index.html"):
                resp.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
        except Exception:
            pass
        return resp

    # Reemplaza/define la ruta raíz para servir el index pastel
    def _root_index_override():
        # Preferir la vista canónica si está registrada
        try:
            vf = app.view_functions.get("front_bp.index")
            if vf:
                resp = vf()
                try:
                    resp.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
                except Exception:
                    pass
                return resp
        except Exception:
            pass

        front_dir = _resolve_front_dir()
        resp = make_response(send_from_directory(front_dir, "index.html"))
        # Cinturón y tirantes: no-store explícito acá también
        resp.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
        return resp

    # Intentamos registrar el endpoint. Si ya existe, reemplazamos la función.
    try:
        app.add_url_rule("/", endpoint="root_index", view_func=_root_index_override, methods=["GET", "HEAD"])
    except Exception:
        # Si el endpoint existe, reasignamos la view function.
        try:
            app.view_functions["root_index"] = _root_index_override
        except Exception:
            # Último recurso: registramos sin endpoint específico
            app.add_url_rule("/", view_func=_root_index_override, methods=["GET", "HEAD"])

    print("[app] root_index activo (frontend canónico + no-store)")
except Exception as _e:
    print("[app] Aviso: no pude instalar root_index/no-store:", _e)
