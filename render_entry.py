from __future__ import annotations
import os, hashlib
from datetime import datetime, timedelta
from flask import Flask, Blueprint, jsonify, request

app = None
db = None
Note = None

# 1) Intenta usar tu factory/ORM reales si existen
try:
    from backend import create_app, db as _db
    from backend.models import Note as _Note
    app = create_app()
    db = _db
    Note = _Note
except Exception:
    pass

# 2) Fallback mínimo si no hay factory/ORM
if app is None:
    from flask_sqlalchemy import SQLAlchemy
    app = Flask(__name__)
    app.config["SQLALCHEMY_DATABASE_URI"] = os.environ.get("DATABASE_URL", "sqlite:///app.db")
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
    db = SQLAlchemy(app)
# ## interactions: startup ensure
try:
    _ensure_interaction_table(app, db)
except Exception:
    pass
    class Note(db.Model):
        __tablename__ = "note"
        id = db.Column(db.Integer, primary_key=True)
        text = db.Column(db.Text, nullable=False)
        timestamp = db.Column(db.DateTime, nullable=False, index=True)
        expires_at = db.Column(db.DateTime, nullable=False, index=True)
        likes = db.Column(db.Integer, default=0, nullable=False)
        views = db.Column(db.Integer, default=0, nullable=False)
        reports = db.Column(db.Integer, default=0, nullable=False)
        author_fp = db.Column(db.String(64), nullable=False, index=True, default="noctx")

def _now(): return datetime.utcnow()
def _fp() -> str:
    try:
        ip = request.headers.get("X-Forwarded-For","") or request.headers.get("CF-Connecting-IP","") or (request.remote_addr or "")
        ua = request.headers.get("User-Agent","")
        salt = os.environ.get("FP_SALT","")
        return hashlib.sha256(f"{ip}|{ua}|{salt}".encode()).hexdigest()[:32]
    except Exception:
        return "noctx"

def _has(path:str, method:str) -> bool:
    for r in app.url_map.iter_rules():
        if str(r) == path and method.upper() in r.methods:
            return True
    return False

def _note_json(n: Note, now: datetime | None = None) -> dict:
    now = now or _now()
    toiso = lambda d: (d.isoformat() if d else None)
    return {
        "id": n.id,
        "text": n.text,
        "timestamp": toiso(getattr(n, "timestamp", None)),
        "expires_at": toiso(getattr(n, "expires_at", None)),
        "likes": getattr(n, "likes", 0),
        "views": getattr(n, "views", 0),
        "reports": getattr(n, "reports", 0),
        "author_fp": getattr(n, "author_fp", None),
        "now": now.isoformat(),
    }

# 3) Blueprint API (debug + fallback /notes si faltaran)
api = Blueprint("api", __name__)

@api.get("/health")
def health():
    # Esto nos permite ver que efectivamente se está usando este entrypoint
    return jsonify(ok=True, note="render_entry"), 200

@api.get("/debug-urlmap")
def debug_urlmap():
    rules = []
    for r in app.url_map.iter_rules():
        methods = sorted([m for m in r.methods if m not in ("HEAD","OPTIONS")])
        rules.append({"rule": str(r), "endpoint": r.endpoint, "methods": methods})
    return jsonify(ok=True, rules=rules), 200

# Solo agrega /api/notes si no existen ya (idempotente)
if Note and not (_has("/api/notes","GET") and _has("/api/notes","POST")):
    @api.get("/notes")
    def list_notes():
        try:
            page = 1
            try: page = max(1, int(request.args.get("page", 1)))
            except Exception: pass
            q = Note.query.order_by(Note.timestamp.desc())
            items = q.limit(20).offset((page-1)*20).all()
            return jsonify([_note_json(n) for n in items]), 200
        except Exception as e:
            return jsonify(ok=False, error="list_failed", detail=str(e)), 500

    @api.post("/notes")
    def create_note():
        from sqlalchemy.exc import SQLAlchemyError

# --- safe default for NOTE_TABLE (evita NameError al importar en Render) ---
import os as _os
NOTE_TABLE = _os.environ.get('NOTE_TABLE','note')
# ---------------------------------------------------------------------------
        try:
            data = request.get_json(silent=True) or {}
            text = (data.get("text") or "").strip()
            if not text:
                return jsonify(error="text required"), 400
            try:
                hours = int(data.get("hours", 24))
            except Exception:
                hours = 24
            hours = min(168, max(1, hours))
            now = _now()
            n = Note(
                text=text,
                timestamp=now,
                expires_at=now + timedelta(hours=hours),
                author_fp=_fp(),
            )
            db.session.add(n)
            db.session.commit()
            return jsonify(_note_json(n, now)), 201
        except SQLAlchemyError as e:
            db.session.rollback()
            return jsonify(ok=False, error="create_failed", detail=str(e)), 500
        except Exception as e:
            return jsonify(ok=False, error="create_failed", detail=str(e)), 500

# 4) Registrar blueprint bajo /api
try:
    app.register_blueprint(api, url_prefix="/api")
except Exception:
    pass

# 5) Crear tablas si faltan (idempotente)
try:
    with app.app_context():
        if db is not None:
            db.create_all()
except Exception:
    pass




# --- bootstrap DB URL normalize (idempotente) ---
def _normalize_database_url(url: str|None):
    if not url: return url
    # Corrige esquema antiguo de Heroku: postgres:// -> postgresql://
    if url.startswith("postgres://"):
        return "postgresql://" + url[len("postgres://"):]
    return url

try:
    import os
    if "SQLALCHEMY_DATABASE_URI" in app.config:
        app.config["SQLALCHEMY_DATABASE_URI"] = _normalize_database_url(app.config.get("SQLALCHEMY_DATABASE_URI"))
    else:
        _env = _normalize_database_url(os.environ.get("DATABASE_URL"))
        if _env:
            app.config["SQLALCHEMY_DATABASE_URI"] = _env
    # create_all best-effort
    try:
        from backend import db
        with app.app_context():
            db.create_all()
    except Exception:
        pass
except Exception:
    pass
from backend.modules.interactions import repair_interaction_table, ensure_schema, register_into, register_alias_into, register_into, register_alias_into, register_into, register_alias_into

##__INTERACTIONS_BOOTSTRAP__
try:
    from flask import current_app as _cap
    _app = _cap._get_current_object() if _cap else app
except Exception:
    _app = app if 'app' in globals() else None

try:
    if _app is not None:
        with _app.app_context():
            try:
                ensure_schema()
            except Exception:  # no romper boot
                pass
            try:
                register_into(_app)
            except Exception:
                pass
            try:
                register_alias_into(_app)
            except Exception:
                pass
except Exception:
    pass

# >>> interactions_bootstrap
try:
    # Localiza el objeto app si existe
    from flask import current_app as _cap
    _app = _cap._get_current_object() if _cap else (app if 'app' in globals() else None)
except Exception:
    _app = app if 'app' in globals() else None

try:
    if _app is not None:
        with _app.app_context():
            # crear tablas por si falta interaction_event
            try:
                ensure_schema()
            except Exception:
                pass
            # registrar blueprints principales
            try:
                register_into(_app)
            except Exception:
                pass
            # registrar alias /api/ix/...
            try:
                register_alias_into(_app)
            except Exception:
                pass
except Exception:
    # no romper inicio
    pass

# (fin bootstrap)

# >>> force_interactions_alias_only (safe, no endpoint collisions)
try:
    from backend.modules import interactions as _ix
    try:
        # asegurar esquema
        from flask import current_app as _cap
        _app = _cap._get_current_object() if _cap else app
    except Exception:
        try:
            _app = app
        except Exception:
            _app = None
    if _app is not None:
        with _app.app_context():
            try:
                _ix.ensure_schema()
            except Exception:
                pass
        # registrar solo alias (/api/ix/notes/*) y el blueprint principal si faltaran diag/stats
        try:
            _ix.register_alias_into(_app)
        except Exception:
            pass
        # Si no existe /api/notes/diag, intentar registrar el bp principal también
        try:
            has_diag = any(str(r)=="/api/notes/diag" for r in _app.url_map.iter_rules())
        except Exception:
            has_diag = False
        if not has_diag:
            try:
                _ix.register_into(_app)
            except Exception:
                pass
except Exception:
    # silencioso para no romper el startup
    pass
# <<< force_interactions_alias_only



# --- DB hardening helpers (idempotente) ---
def _normalize_database_url(url: str|None):
    if not url:
        return url
    # Corrige postgres:// -> postgresql://
    if url.startswith("postgres://"):
        url = "postgresql://" + url[len("postgres://"):]
    # Asegura sslmode=require si no está presente
    if "sslmode=" not in url:
        sep = "&" if "?" in url else "?"
        url = f"{url}{sep}sslmode=require"
    return url

def apply_engine_hardening(app):
    # Motor con pre_ping y recycle para evitar EOF/idle disconnects
    app.config.setdefault("SQLALCHEMY_ENGINE_OPTIONS", {})
    opts = app.config["SQLALCHEMY_ENGINE_OPTIONS"]
    opts.setdefault("pool_pre_ping", True)
    opts.setdefault("pool_recycle", 300)
    opts.setdefault("pool_size", 5)
    opts.setdefault("max_overflow", 10)
    opts.setdefault("pool_timeout", 30)
    app.config["SQLALCHEMY_ENGINE_OPTIONS"] = opts


# create_all con retry para evitar fallos transitorios de red/SSL
def _retry_create_all(db, app, tries=5):
    import time
    for i in range(tries):
        try:
            with app.app_context():
                db.create_all()
            return True
        except Exception as e:
            # backoff simple
            time.sleep(1 + i)
    return False

try:
    _retry_create_all(db, app)
except Exception:
    pass


# === ensure: interacción (solo tabla interaction_event) ===
def _ensure_interaction_table(app, db):
    try:
        # Normalizar URL y endurecer engine si tu archivo ya tiene helpers:
        try:
            app.config["SQLALCHEMY_DATABASE_URI"] = _normalize_database_url(
                app.config.get("SQLALCHEMY_DATABASE_URI")
            )
        except Exception:
            pass
        # Crear exclusivamente la tabla de eventos (idempotente)
        from sqlalchemy import inspect
        insp = inspect(db.engine)
        if "interaction_event" not in insp.get_table_names():
            InteractionEvent.__table__.create(bind=db.engine, checkfirst=True)
        # Crear resto si faltara algo (seguro/idempotente)
        ensure_schema()
        return True
    except Exception:
        return False


# === endpoint de mantenimiento: POST /api/notes/ensure-schema ===
try:
    from flask import Blueprint, jsonify
    _mnt = Blueprint("interactions_maint", __name__)

    @_mnt.post("/notes/ensure-schema", endpoint="ensure_interaction_schema")
    def ensure_interaction_schema():
        try:
            ok = _ensure_interaction_table(app, db)
            return jsonify(ok=bool(ok), created=True), (200 if ok else 500)
        except Exception as e:
            return jsonify(ok=False, error="ensure_failed", detail=str(e)), 500

    try:
        app.register_blueprint(_mnt, url_prefix="/api")
    except Exception:
        pass
except Exception:
    pass


# === mantenimiento: POST /api/notes/repair-interactions ===
try:
    from flask import Blueprint, jsonify
    _mnt2 = Blueprint("interactions_repair", __name__)

    @_mnt2.post("/notes/repair-interactions", endpoint="repair_interaction_schema")
    def _repair_interactions():
        try:
            ok = repair_interaction_table()
            return jsonify(ok=bool(ok)), (200 if ok else 500)
        except Exception as e:
            return jsonify(ok=False, error="repair_failed", detail=str(e)), 500

    try:
        app.register_blueprint(_mnt2, url_prefix="/api")
    except Exception:
        pass
except Exception:
    pass


# === interactions: ensure schema + alias (/api/ix) ==========================
try:
    from backend.modules.interactions import register_alias_into, ensure_schema
    try:
        with app.app_context():
            ensure_schema()
    except Exception:
        pass
    try:
        register_alias_into(app)  # /api/ix/notes/<id>/(like|view|stats)
    except Exception:
        pass
except Exception:
    # si no está el módulo, no rompemos el arranque
    pass
# ===========================================================================


# --- POST /api/notes/repair-interactions: recrea esquema de interactions ----
try:
    from flask import Blueprint as _BP, jsonify as _jsonify
    _repair_bp = _BP("repair_interactions_bp", __name__)
    @_repair_bp.post("/api/notes/repair-interactions", endpoint="repair_interactions")
    def _repair_interactions():
        try:
            from backend.modules.interactions import ensure_schema
            with app.app_context():
                ensure_schema()
            return _jsonify(ok=True, note="ensure_schema() done"), 200
        except Exception as e:
            return _jsonify(ok=False, error="repair_failed", detail=str(e)), 500
    try:
        app.register_blueprint(_repair_bp)
    except Exception:
        pass
except Exception:
    pass
# ----------------------------------------------------------------------------

# (old interactions bootstrap removed)


# --- interactions bootstrap (CLEAN, idempotent) ---
try:
    from backend.modules.interactions import (
        bp as _ix_bp,
        alias_bp as _ix_alias_bp,
        ensure_schema as _ix_ensure_schema,
    )
except Exception as _e_ix:
    _ix_bp = None
    _ix_alias_bp = None
    def _ix_ensure_schema():
        return None

def _ix_register_blueprints(_app):
    try:
        if _ix_ensure_schema:
            with _app.app_context():
                _ix_ensure_schema()
        if _ix_bp is not None:
            try: _app.register_blueprint(_ix_bp, url_prefix="/api")
            except Exception: pass
        if _ix_alias_bp is not None:
            try: _app.register_blueprint(_ix_alias_bp, url_prefix="/api")
            except Exception: pass
    except Exception:
        pass

try:
    _ix_register_blueprints(app)
except Exception:
    pass

from flask import Blueprint as _IXBP, jsonify as _jsonify
_ixdiag = _IXBP("ixdiag_render_entry", __name__)

@_ixdiag.get("/notes/diag")
def _ix_notes_diag():
    try:
        from sqlalchemy import inspect as _inspect, func as _func
        eng = db.get_engine()
        inspector = _inspect(eng)
        tables = inspector.get_table_names()
        has_evt = "interaction_event" in tables
        out = {"tables": tables, "has_interaction_event": has_evt}
        if has_evt:
            from backend.modules.interactions import InteractionEvent
            likes_cnt = db.session.query(_func.count(InteractionEvent.id)).filter_by(type="like").scalar() or 0
            views_cnt = db.session.query(_func.count(InteractionEvent.id)).filter_by(type="view").scalar() or 0
            out["total_likes"] = int(likes_cnt); out["total_views"] = int(views_cnt)
        return _jsonify(ok=True, **out), 200
    except Exception as e:
        return _jsonify(ok=False, error="diag_failed", detail=str(e)), 500

@_ixdiag.post("/notes/repair-interactions")
def _ix_repair_interactions():
    try:
        if _ix_ensure_schema:
            with app.app_context():
                _ix_ensure_schema()
        return _jsonify(ok=True, repaired=True), 200
    except Exception as e:
        return _jsonify(ok=False, error="repair_failed", detail=str(e)), 500

try:
    app.register_blueprint(_ixdiag, url_prefix="/api")
except Exception:
    pass
# --- end interactions bootstrap


# --- interactions bootstrap (CLEAN, idempotent) ---
try:
    from backend.modules.interactions import (
        bp as _ix_bp,
        alias_bp as _ix_alias_bp,
        ensure_schema as _ix_ensure_schema,
    )
except Exception as _e_ix:
    _ix_bp = None
    _ix_alias_bp = None
    def _ix_ensure_schema():
        return None

def _ix_register_blueprints(_app):
    try:
        if _ix_ensure_schema:
            with _app.app_context():
                _ix_ensure_schema()
        if _ix_bp is not None:
            try: _app.register_blueprint(_ix_bp, url_prefix="/api")
            except Exception: pass
        if _ix_alias_bp is not None:
            try: _app.register_blueprint(_ix_alias_bp, url_prefix="/api")
            except Exception: pass
    except Exception:
        pass

try:
    _ix_register_blueprints(app)
except Exception:
    pass

from flask import Blueprint as _IXBP, jsonify as _jsonify
_ixdiag = _IXBP("ixdiag_render_entry", __name__)

@_ixdiag.get("/notes/diag")
def _ix_notes_diag():
    try:
        from sqlalchemy import inspect as _inspect, func as _func
        eng = db.get_engine()
        inspector = _inspect(eng)
        tables = inspector.get_table_names()
        has_evt = "interaction_event" in tables
        out = {"tables": tables, "has_interaction_event": has_evt}
        if has_evt:
            from backend.modules.interactions import InteractionEvent
            likes_cnt = db.session.query(_func.count(InteractionEvent.id)).filter_by(type="like").scalar() or 0
            views_cnt = db.session.query(_func.count(InteractionEvent.id)).filter_by(type="view").scalar() or 0
            out["total_likes"] = int(likes_cnt); out["total_views"] = int(views_cnt)
        return _jsonify(ok=True, **out), 200
    except Exception as e:
        return _jsonify(ok=False, error="diag_failed", detail=str(e)), 500

@_ixdiag.post("/notes/repair-interactions")
def _ix_repair_interactions():
    try:
        if _ix_ensure_schema:
            with app.app_context():
                _ix_ensure_schema()
        return _jsonify(ok=True, repaired=True), 200
    except Exception as e:
        return _jsonify(ok=False, error="repair_failed", detail=str(e)), 500

try:
    app.register_blueprint(_ixdiag, url_prefix="/api")
except Exception:
    pass
# --- end interactions bootstrap


# --- interactions bootstrap (CLEAN, idempotent) ---
try:
    from backend.modules.interactions import (
        bp as _ix_bp,
        alias_bp as _ix_alias_bp,
        ensure_schema as _ix_ensure_schema,
    )
except Exception as _e_ix:
    _ix_bp = None
    _ix_alias_bp = None
    def _ix_ensure_schema():
        return None

def _ix_register_blueprints(_app):
    try:
        if _ix_ensure_schema:
            with _app.app_context():
                _ix_ensure_schema()
        if _ix_bp is not None:
            try: _app.register_blueprint(_ix_bp, url_prefix="/api")
            except Exception: pass
        if _ix_alias_bp is not None:
            try: _app.register_blueprint(_ix_alias_bp, url_prefix="/api")
            except Exception: pass
    except Exception:
        pass

try:
    _ix_register_blueprints(app)
except Exception:
    pass

from flask import Blueprint as _IXBP, jsonify as _jsonify
_ixdiag = _IXBP("ixdiag_render_entry", __name__)

@_ixdiag.get("/notes/diag")
def _ix_notes_diag():
    try:
        from sqlalchemy import inspect as _inspect, func as _func
        eng = db.get_engine()
        inspector = _inspect(eng)
        tables = inspector.get_table_names()
        has_evt = "interaction_event" in tables
        out = {"tables": tables, "has_interaction_event": has_evt}
        if has_evt:
            from backend.modules.interactions import InteractionEvent
            likes_cnt = db.session.query(_func.count(InteractionEvent.id)).filter_by(type="like").scalar() or 0
            views_cnt = db.session.query(_func.count(InteractionEvent.id)).filter_by(type="view").scalar() or 0
            out["total_likes"] = int(likes_cnt); out["total_views"] = int(views_cnt)
        return _jsonify(ok=True, **out), 200
    except Exception as e:
        return _jsonify(ok=False, error="diag_failed", detail=str(e)), 500

@_ixdiag.post("/notes/repair-interactions")
def _ix_repair_interactions():
    try:
        if _ix_ensure_schema:
            with app.app_context():
                _ix_ensure_schema()
        return _jsonify(ok=True, repaired=True), 200
    except Exception as e:
        return _jsonify(ok=False, error="repair_failed", detail=str(e)), 500

try:
    app.register_blueprint(_ixdiag, url_prefix="/api")
except Exception:
    pass
# --- end interactions bootstrap

