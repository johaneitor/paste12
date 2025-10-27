import os
import logging
from flask import Flask, jsonify, request, g
from flask_cors import CORS
from flask_sqlalchemy import SQLAlchemy
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from time import perf_counter
import sqlite3
from sqlalchemy import event
from sqlalchemy.engine import Engine
from sqlalchemy.exc import OperationalError

db = SQLAlchemy()

# Global rate limiter (initialized in create_app)
# Default policy aligned with spec: 300 requests per hour for general GETs
limiter: Limiter = Limiter(key_func=get_remote_address, default_limits=["300 per hour"]) 

def create_app():
    app = Flask(__name__)

    # --- DB URL (con fallback) ---
    db_url = os.environ.get("DATABASE_URL") or os.environ.get("SQLALCHEMY_DATABASE_URI")
    if db_url and db_url.startswith("postgres://"):
        db_url = db_url.replace("postgres://", "postgresql://", 1)
    app.config["SQLALCHEMY_DATABASE_URI"] = db_url or "sqlite:////tmp/paste12.db"
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

    # Engine options tuned for SQLite/Postgres; safe defaults for others
    engine_opts = {"pool_pre_ping": True, "pool_recycle": 280}
    try:
        if db_url and db_url.startswith("postgresql"):
            # Conservative pool for small apps
            engine_opts.update({"pool_size": 10, "max_overflow": 20})
        elif (db_url or "").startswith("sqlite") or (not db_url):
            # Busy timeout helps reduce "database is locked" under write contention
            engine_opts.update({"connect_args": {"timeout": 5.0}})
    except Exception:
        pass
    app.config.setdefault("SQLALCHEMY_ENGINE_OPTIONS", engine_opts)

    # --- CORS sólo para /api/* ---
    # Afinar CORS: allowlist configurable por env (coma-separada) y default a URL pública
    try:
        allowlist = os.environ.get("P12_CORS_ALLOWLIST", "").strip()
        if allowlist:
            origins = [o.strip() for o in allowlist.split(",") if o.strip()]
        else:
            origins = [os.environ.get("PUBLIC_BASE_URL", "https://paste12-rmsk.onrender.com").rstrip("/")]
        CORS(
            app,
            resources={r"/api/*": {
                "origins": origins,
                "allow_headers": ["Content-Type", "X-Requested-With", "X-FP"],
                "methods": ["GET", "POST", "OPTIONS"],
                "supports_credentials": False,
            }},
        )
    except Exception:
        # Fallback a CORS abierto en caso de error de config, pero sin credenciales
        CORS(app, resources={r"/api/*": {"origins": "*"}}, supports_credentials=False)

    # --- SQLAlchemy init ---
    db.init_app(app)

    # Apply SQLite pragmas globally on connect (affects all SQLAlchemy engines in-process)
    @event.listens_for(Engine, "connect")
    def _set_sqlite_pragmas(dbapi_conn, _):  # type: ignore[override]
        try:
            if isinstance(dbapi_conn, sqlite3.Connection):
                cur = dbapi_conn.cursor()
                try:
                    cur.execute("PRAGMA journal_mode=WAL")
                except Exception:
                    pass
                try:
                    cur.execute("PRAGMA busy_timeout=5000")
                except Exception:
                    pass
                try:
                    cur.execute("PRAGMA synchronous=NORMAL")
                except Exception:
                    pass
                cur.close()
        except Exception:
            # Never break connection setup because of PRAGMA attempts
            pass

    # Simple response-time header for observability
    @app.before_request
    def _p12_t0():
        try:
            g._p12_t0 = perf_counter()
        except Exception:
            pass

    @app.after_request
    def _p12_resp_time(resp):
        try:
            t0 = getattr(g, "_p12_t0", None)
            if t0 is not None:
                dt_ms = (perf_counter() - t0) * 1000.0
                resp.headers.setdefault("X-Resp-Time", f"{dt_ms:.1f}ms")
        except Exception:
            pass
        return resp

    # --- Rate limit storage config (prefer Redis in prod) ---
    # Guard against literal "$PORT" in FLASK_LIMITER_STORAGE_URI (e.g., redis://:pwd@host:$PORT/0)
    # which can break URL parsing in limits/flask-limiter on Render native builds.
    try:
        raw_storage_uri = os.environ.get("FLASK_LIMITER_STORAGE_URI")
        resolved_storage_uri = "memory://"
        if raw_storage_uri:
            candidate = raw_storage_uri
            if "$PORT" in candidate:
                env_port = os.environ.get("PORT")
                if env_port and env_port.isdigit():
                    candidate = candidate.replace("$PORT", env_port)
                else:
                    app.logger.warning(
                        "[limiter] FLASK_LIMITER_STORAGE_URI contains literal $PORT and no numeric PORT env; using memory://"
                    )
                    candidate = "memory://"
            resolved_storage_uri = candidate
        app.config.setdefault("RATELIMIT_STORAGE_URI", resolved_storage_uri)
    except Exception as _exc:
        # Fallback to in-memory storage if anything goes wrong during resolution
        try:
            app.logger.warning("[limiter] storage URI resolution failed: %r; using memory://", _exc)
        except Exception:
            pass

    # --- Ensure minimal schema (non-intrusive) ---
    try:
        with app.app_context():
            from sqlalchemy import text as _text

            # Ensure models are loaded and base tables exist
            from . import models as _models  # noqa: F401
            db.create_all()

            # Minimal auxiliary tables for idempotent logs
            db.session.execute(_text(
                """
                CREATE TABLE IF NOT EXISTS note_report (
                  note_id INTEGER NOT NULL,
                  reporter_hash TEXT NOT NULL,
                  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                  UNIQUE(note_id, reporter_hash)
                )
                """
            ))
            db.session.execute(_text(
                """
                CREATE TABLE IF NOT EXISTS note_view (
                  note_id INTEGER NOT NULL,
                  fp TEXT NOT NULL,
                  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                  UNIQUE(note_id, fp)
                )
                """
            ))
            db.session.execute(_text(
                """
                CREATE TABLE IF NOT EXISTS note_like (
                  note_id INTEGER NOT NULL,
                  fp TEXT NOT NULL,
                  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                  UNIQUE(note_id, fp)
                )
                """
            ))

            # Ensure counters exist (likes/views/reports) for legacy DBs
            def _ensure_counter_columns(table_name: str) -> None:
                for col, ddl in (
                    ("likes",   "INTEGER NOT NULL DEFAULT 0"),
                    ("views",   "INTEGER NOT NULL DEFAULT 0"),
                    ("reports", "INTEGER NOT NULL DEFAULT 0"),
                ):
                    try:
                        db.session.execute(_text(f"ALTER TABLE {table_name} ADD COLUMN IF NOT EXISTS {col} {ddl}"))
                    except Exception:
                        try:
                            db.session.execute(_text(f"ALTER TABLE {table_name} ADD COLUMN {col} {ddl}"))
                        except Exception:
                            pass

            # Apply for both historic names
            for tbl in ("notes", "note"):
                _ensure_counter_columns(tbl)

            # Soft-delete column (may already exist)
            for tbl in ("notes", "note"):
                try:
                    db.session.execute(_text(f"ALTER TABLE {tbl} ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP NULL"))
                except Exception:
                    try:
                        db.session.execute(_text(f"ALTER TABLE {tbl} ADD COLUMN deleted_at TIMESTAMP NULL"))
                    except Exception:
                        pass

            # --- Guard triggers to avoid FK violations on log tables (Postgres) ---
            try:
                # Only run on Postgres; SQLite ignores DDL and has no triggers here
                import sqlalchemy as _sa  # lazy import
                dialect = db.engine.dialect.name
                if dialect.startswith("postgres"):
                    # Ensure log tables exist (compat with interactions module)
                    db.session.execute(_text(
                        """
                        CREATE TABLE IF NOT EXISTS like_log(
                          note_id INTEGER NOT NULL,
                          fingerprint VARCHAR(128) NOT NULL,
                          created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
                        )
                        """
                    ))
                    db.session.execute(_text(
                        """
                        CREATE TABLE IF NOT EXISTS view_log(
                          note_id INTEGER NOT NULL,
                          fingerprint VARCHAR(128) NOT NULL,
                          day TEXT NOT NULL,
                          created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
                        )
                        """
                    ))
                    db.session.execute(_text(
                        """
                        CREATE TABLE IF NOT EXISTS report_log(
                          note_id INTEGER NOT NULL,
                          fingerprint VARCHAR(128) NOT NULL,
                          reason TEXT,
                          created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
                        )
                        """
                    ))

                    # Create guard function
                    db.session.execute(_text(
                        """
                        CREATE OR REPLACE FUNCTION ensure_parent_note_exists() RETURNS trigger
                        LANGUAGE plpgsql AS $$
                        BEGIN
                          IF NOT EXISTS (SELECT 1 FROM note WHERE id = NEW.note_id) THEN
                            RETURN NULL; -- skip insert if parent note missing
                          END IF;
                          RETURN NEW;
                        END
                        $$;
                        """
                    ))

                    # Triggers for each log table
                    for _tbl, _trg in (
                        ("view_log",   "trg_view_log_guard"),
                        ("like_log",   "trg_like_log_guard"),
                        ("report_log", "trg_report_log_guard"),
                    ):
                        try:
                            db.session.execute(_text(f"DROP TRIGGER IF EXISTS {_trg} ON {_tbl}"))
                        except Exception:
                            pass
                        db.session.execute(_text(
                            f"""
                            CREATE TRIGGER {_trg}
                            BEFORE INSERT ON {_tbl}
                            FOR EACH ROW EXECUTE FUNCTION ensure_parent_note_exists()
                            """
                        ))
            except Exception as _e:
                # Do not block app startup on DDL failures
                try:
                    logging.getLogger(__name__).warning("[schema] trigger guards setup skipped: %r", _e)
                except Exception:
                    pass

            db.session.commit()
    except Exception as _exc:
        logging.getLogger(__name__).warning("[schema] ensure note_report skipped: %r", _exc)

    # --- Early guard for legacy alias /api/report to ensure 404 on bad/missing id ---
    @app.before_request
    def _guard_alias_report_early():
        try:
            if request.path == "/api/report" and request.method in ("GET", "POST"):
                raw = request.args.get("id") or request.form.get("id")
                if not raw:
                    return jsonify(error="bad_id"), 404
                try:
                    int(raw)
                except Exception:
                    return jsonify(error="bad_id"), 404
        except Exception:
            # Do not block request flow on guard exception
            return None

    # --- Canonical alias endpoint for /api/report (takes precedence) ---
    @app.route("/api/report", methods=["GET", "POST"])
    def _report_alias_canonical():
        # Legacy alias disabled: always respond 404 to avoid legacy handlers.
        return jsonify(error="not_found"), 404

    # --- Legacy like alias to homogenize negatives ---
    @app.route("/api/like", methods=["GET", "POST"])  # ensure 404/405 similar to view/report
    def _like_alias_canonical():
        # Require numeric id like other aliases; otherwise respond 404
        nid = (request.args.get("id") if request.method == "GET" else (request.get_json(silent=True) or {}).get("id"))
        try:
            nid_int = int(nid)
        except Exception:
            return jsonify(error="not_found"), 404
        # We don't implement side-effects here; this legacy alias is disabled
        return jsonify(error="not_found"), 404

    # --- Rate limiter (default 200/min global) ---
    try:
        # In production you should configure FLASK_LIMITER_STORAGE_URI (e.g., redis://)
        # to avoid in-memory storage.
        limiter.init_app(app)
    except Exception as exc:
        logging.getLogger(__name__).warning("[limiter] init failed: %r", exc)

    # --- API (si falla import, queda fallback limpio) ---
    try:
        from .routes import api_bp  # type: ignore
        app.register_blueprint(api_bp, url_prefix="/api")
    except Exception as exc:
        app.logger.error("[api] fallback: no pude registrar api_bp: %r", exc)

        # Guardar el detalle en una variable local (el binding del 'exc' de except
        # se limpia tras salir del bloque en Python 3). Evitamos capturar 'exc'.
        _api_fallback_detail = str(exc)

        @app.route("/api/health")
        def _health_fallback():
            # Do not leak internal exception details unless explicitly enabled
            body = {"ok": True, "api": False, "ver": "factory-fallback"}
            if os.environ.get("P12_HEALTH_DETAIL", "0") == "1":
                body["detail"] = _api_fallback_detail
            resp = jsonify(**body)
            try:
                resp.headers["Cache-Control"] = "no-store"
            except Exception:
                pass
            return resp, 200

        # Asegurar que el health nunca sea limitado por tasa
        try:
            limiter.exempt(_health_fallback)
        except Exception:
            pass

        # No definir fallback de /api/notes aquí para permitir que la cápsula
        # de notas se registre más abajo si está disponible.

    # --- Asegurar /api/notes mínimo si falta ---
    try:
        from .routes_notes import register_api as _register_notes  # type: ignore
        _register_notes(app)
    except Exception as _e:
        app.logger.warning("[api] notes capsule not registered: %r", _e)

    # --- Registrar interacciones (like/view/report) si el módulo está disponible ---
    try:
        from .modules.interactions import register_into as _register_interactions  # type: ignore
        _register_interactions(app)
    except Exception as _e:
        app.logger.warning("[api] interactions not registered: %r", _e)

        # Minimal safe fallbacks to avoid 500s when interactions module isn't available
        from sqlalchemy import text as _text

        @app.post("/api/notes/<int:note_id>/like")
        def _like_fallback(note_id: int):
            try:
                with app.app_context():
                    db.session.execute(_text("UPDATE notes SET likes = COALESCE(likes,0)+1 WHERE id=:id"), {"id": note_id})
                    row = db.session.execute(_text("SELECT id, COALESCE(likes,0) AS likes FROM notes WHERE id=:id"), {"id": note_id}).first()
                    db.session.commit()
                if not row:
                    return jsonify(ok=False, error="not_found"), 404
                return jsonify(ok=True, id=row.id, likes=row.likes), 200
            except Exception as exc:
                db.session.rollback()
                msg = str(exc).lower()
                if "database is locked" in msg or "deadlock" in msg or "timeout" in msg:
                    return jsonify(ok=False, error="db_busy"), 503
                return jsonify(ok=False, error="server_error"), 500

        @app.post("/api/notes/<int:note_id>/report")
        def _report_fallback(note_id: int):
            try:
                with app.app_context():
                    db.session.execute(_text("UPDATE notes SET reports = COALESCE(reports,0)+1 WHERE id=:id"), {"id": note_id})
                    row = db.session.execute(_text("SELECT id, COALESCE(reports,0) AS reports FROM notes WHERE id=:id"), {"id": note_id}).first()
                    db.session.commit()
                if not row:
                    return jsonify(ok=False, error="not_found"), 404
                return jsonify(ok=True, id=row.id, reports=row.reports), 200
            except Exception as exc:
                db.session.rollback()
                msg = str(exc).lower()
                if "database is locked" in msg or "deadlock" in msg or "timeout" in msg:
                    return jsonify(ok=False, error="db_busy"), 503
                return jsonify(ok=False, error="server_error"), 500

    # --- Frontend blueprint (sirve /, /terms, /privacy) ---
    try:
        from .front_bp import front_bp  # type: ignore
        app.register_blueprint(front_bp)
    except Exception as exc:
        app.logger.warning("[front] blueprint no registrado: %r", exc)

        @app.route("/")
        def _index_min():
            return "<!doctype html><title>Paste12</title><h1>Paste12</h1>", 200

    # --- Health mínimo (si ya existe en api_bp, este no molesta) ---
    @app.get("/api/health")
    @limiter.exempt
    def api_health():
        resp = jsonify(ok=True, status="ok", api=True, ver="factory-min-v1")
        try:
            resp.headers["Cache-Control"] = "no-store"
        except Exception:
            pass
        return resp, 200

    # --- Platform healthz (Render/ALB probes) ---
    # Define only one /healthz endpoint with JSON body, idempotent
    @app.get("/healthz")
    @limiter.exempt
    def healthz():
        resp = jsonify(ok=True)
        try:
            resp.headers["Cache-Control"] = "no-store"
        except Exception:
            pass
        return resp, 200

    # --- Health DB (opcional) ---
    @app.get("/api/health/db")
    def api_health_db():
        try:
            from sqlalchemy import text as _text
            with app.app_context():
                # Simple round-trip and basic metrics
                db.session.execute(_text("SELECT 1"))
                metrics = {"ok": True, "db": True}
                try:
                    dname = db.engine.dialect.name
                    metrics["dialect"] = dname
                    if dname.startswith("postgres"):
                        used = db.session.execute(_text("SELECT count(*) FROM pg_stat_activity"))
                        maxc = db.session.execute(_text("SHOW max_connections"))
                        used_n = int(list(used)[0][0]) if used else None
                        max_n = int(list(maxc)[0][0]) if maxc else None
                        metrics.update({"connections": used_n, "max_connections": max_n})
                except Exception:
                    pass
            return jsonify(**metrics), 200
        except Exception as exc:
            return jsonify(ok=False, db=False, error=str(exc)), 500

    # --- Uniform JSON error responses for /api/* ---
    @app.errorhandler(404)
    def _json_404(err):
        try:
            if request.path.startswith("/api/"):
                return jsonify(error="not_found"), 404
        except Exception:
            # Fall through to default HTML error page
            pass
        # For non-API routes, delegate to Flask's default 404 page
        return err

    # --- Debug/diagnostic helpers used by smoke scripts ---
    @app.get("/__whoami")
    @limiter.exempt
    def __whoami():
        try:
            bl = sorted(list(app.blueprints.keys()))
        except Exception:
            bl = []
        has_detail = False
        try:
            for r in app.url_map.iter_rules():
                s = str(r)
                if s in ("/api/notes/<int:note_id>", "/api/notes/<int:note_id>/like", "/api/notes/<int:note_id>/report"):
                    has_detail = True
                    break
        except Exception:
            pass
        return jsonify(blueprints=bl, has_detail_routes=has_detail), 200

    @app.get('/api/_routes')
    @limiter.exempt
    def api_routes_dump():
        routes = []
        try:
            for r in app.url_map.iter_rules():
                routes.append({
                    "rule": str(r),
                    "methods": sorted(list(r.methods or [])),
                    "endpoint": r.endpoint,
                })
        except Exception:
            pass
        return jsonify(routes=routes), 200

    @app.errorhandler(400)
    def _json_400(err):
        try:
            if request.path.startswith("/api/"):
                return jsonify(error="bad_request"), 400
        except Exception:
            # Fall through to default HTML error page
            pass
        # For non-API routes, delegate to Flask's default 400 page
        return err

    @app.errorhandler(405)
    def _json_405(err):
        try:
            if request.path.startswith("/api/"):
                # Include Allow header if available from exception
                resp = jsonify(error="method_not_allowed")
                try:
                    allow = getattr(err, "valid_methods", None)
                    if allow:
                        resp.headers["Allow"] = ", ".join(allow)
                except Exception:
                    pass
                return resp, 405
        except Exception:
            # Fall through to default HTML error page
            pass
        # For non-API routes, delegate to Flask's default 405 page
        return err

    # Map DB lock/timeouts to 503 for API calls so clients can retry gracefully
    @app.errorhandler(OperationalError)
    def _db_operational_to_503(err):
        try:
            if request.path.startswith("/api/"):
                msg = str(getattr(err, "orig", err)).lower()
                if "database is locked" in msg or "deadlock" in msg or "timeout" in msg:
                    return jsonify(ok=False, error="db_busy"), 503
        except Exception:
            pass
        return err

    # --- Optional secure headers (enable with P12_SECURE_HEADERS=1) ---
    if os.environ.get("P12_SECURE_HEADERS", "0") == "1":
        @app.after_request
        def _secure_headers(resp):
            try:
                resp.headers.setdefault("Strict-Transport-Security", "max-age=31536000; includeSubDomains; preload")
                resp.headers.setdefault("X-Frame-Options", "DENY")
                resp.headers.setdefault("X-Content-Type-Options", "nosniff")
                resp.headers.setdefault("Referrer-Policy", "no-referrer")
            except Exception:
                pass
            return resp

    # --- Content-Security-Policy via header for HTML responses ---
    @app.after_request
    def _csp_header(resp):
        try:
            ct = (resp.headers.get("Content-Type") or "").lower()
            if "text/html" in ct:
                # Endurecer CSP progresivamente: permitir ads sólo si están habilitados
                allow_ads = os.environ.get("P12_ENABLE_ADS", "1") == "1"
                script_src = ["'self'"]
                img_src = ["'self'", "data:"]
                connect_src = ["'self'"]
                frame_src = []
                if allow_ads:
                    script_src += [
                        "https://pagead2.googlesyndication.com",
                        "https://googleads.g.doubleclick.net",
                    ]
                    img_src += [
                        "https://pagead2.googlesyndication.com",
                        "https://googleads.g.doubleclick.net",
                        "https://www.google.com",
                        "https://www.googletagservices.com",
                    ]
                    connect_src += [
                        "https://pagead2.googlesyndication.com",
                        "https://googleads.g.doubleclick.net",
                    ]
                    frame_src += [
                        "https://googleads.g.doubleclick.net",
                        "https://tpc.googlesyndication.com",
                    ]

                # Style policy: allow inline styles for now to avoid breaking ads/widgets.
                # Consider migrating to hashes/nonces and removing 'unsafe-inline'.
                csp = (
                    "default-src 'self'; "
                    "base-uri 'self'; form-action 'self'; frame-ancestors 'self'; "
                    f"script-src {' '.join(script_src)}; "
                    f"img-src {' '.join(img_src)}; "
                    "style-src 'self' 'unsafe-inline'; "
                    f"connect-src {' '.join(connect_src)}; "
                    f"frame-src {' '.join(frame_src) if frame_src else "'none'"}; "
                    "object-src 'none'; upgrade-insecure-requests"
                )
                # Enforce a single unified CSP header for all HTML responses
                resp.headers["Content-Security-Policy"] = csp
        except Exception:
            pass
        return resp

    return app
