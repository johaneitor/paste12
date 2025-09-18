# --- P12 SAFE EXPORT (prepend) ---
def _p12_try_entry_app():
    try:
        from entry_main import app as _a
        return _a if callable(_a) else None
    except Exception:
        return None

def _p12_try_legacy_resolver():
    try:
        ra = globals().get("_resolve_app")
        if callable(ra):
            a = ra()
            return a if a else None
    except Exception:
        return None
    return None

def application(environ, start_response):
    a = _p12_try_entry_app() or _p12_try_legacy_resolver()
    if a is None:
        start_response("500 Internal Server Error", [("Content-Type","text/plain; charset=utf-8")])
        return [b"wsgiapp: no pude resolver la WSGI app (entry_main o _resolve_app)"]
    return a(environ, start_response)

app = application
# --- END P12 SAFE EXPORT ---
# --- P12 SAFE EXPORT (prepend) ---
def _p12_try_entry_app():
    try:
        from entry_main import app as _a
        return _a if callable(_a) else None
    except Exception:
        return None

def _p12_try_legacy_resolver():
    try:
        # Si _resolve_app existe más abajo, lo tomamos cuando el módulo termine de cargar
        ra = globals().get("_resolve_app")
        if callable(ra):
            a = ra()
            return a if a else None
    except Exception:
        return None

def app(environ, start_response):
    a = _p12_try_entry_app() or _p12_try_legacy_resolver()
    if a is None:
        start_response("500 Internal Server Error", [("Content-Type","text/plain; charset=utf-8")])
        return [b"wsgiapp: no pude resolver la WSGI app (entry_main o _resolve_app)"]
    return a(environ, start_response)

application = app
# --- END P12 SAFE EXPORT ---

from sqlalchemy import text as _text

def _json(code, payload):
    """(status, headers, body) JSON estándar, no-store, idempotente"""
    body = _json_mod.dumps(payload, default=str).encode("utf-8")
    status = f"{code} OK"
    headers = [
        ("Content-Type", "application/json; charset=utf-8"),
        ("Content-Length", str(len(body))),
        ("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0"),
        ("X-WSGI-Bridge", "1"),
    ]
    return status, headers, body

T = _text
import os, sys, json, mimetypes, hashlib
from importlib import import_module
from typing import Callable, Tuple
from datetime import datetime, timedelta, timezone

def _inject_single_meta(body_bytes):
    try:
        b = body_bytes if isinstance(body_bytes, (bytes, bytearray)) else (body_bytes or b"")
        if not b:
            return body_bytes
        if (b.find(b'data-single="1"') != -1) and (b.find(b'name="p12-single"') == -1):
            return b.replace(b"<head", b"<head><meta name=\"p12-single\" content=\"1\">", 1)
    except Exception:
        pass
    return body_bytes

_THIS = os.path.abspath(__file__)
_REPO_DIR = os.path.dirname(os.path.dirname(_THIS))
if _REPO_DIR not in sys.path:
    sys.path.insert(0, _REPO_DIR)

CANDIDATES = ["app:app", "run:app", "render_entry:app", "entry_main:app"]

def _resolve_app():
    last_err = None
    for spec in CANDIDATES:
        try:
            os.environ["APP_MODULE"] = spec
            sys.modules.pop("patched_app", None)
            pa = import_module("patched_app")
            return getattr(pa, "app")
        except Exception as e:
            last_err = e
    print(f"[wsgiapp] WARNING: no pude resolver APP_MODULE (probados {CANDIDATES}). Último error: {last_err!r}")
    return None

def _bootstrap_db():
    from sqlalchemy import create_engine, text
    url = os.environ.get("DATABASE_URL", "") or os.environ.get("SQLALCHEMY_DATABASE_URI","")
    if not url:
        return
    eng = create_engine(url, pool_pre_ping=True)
    with eng.begin() as cx:
        cx.execute(text("""
            CREATE TABLE IF NOT EXISTS note(
                id SERIAL PRIMARY KEY,
                title TEXT, url TEXT, summary TEXT, content TEXT,
                text TEXT,
                timestamp TIMESTAMPTZ DEFAULT NOW(),
                expires_at TIMESTAMPTZ,
                likes INT DEFAULT 0,
                views INT DEFAULT 0,
                reports INT DEFAULT 0,
                author_fp VARCHAR(64)
            )
        """))
        cx.execute(text("""
            CREATE TABLE IF NOT EXISTS report_log(
                id SERIAL PRIMARY KEY,
                note_id INT NOT NULL,
                fingerprint VARCHAR(128) NOT NULL,
                created_at TIMESTAMPTZ DEFAULT NOW()
            )
        """))
        cx.execute(text("""
            CREATE TABLE IF NOT EXISTS like_log(
                id SERIAL PRIMARY KEY,
                note_id INT NOT NULL,
                fingerprint VARCHAR(128) NOT NULL,
                created_at TIMESTAMPTZ DEFAULT NOW()
            )
        """))
        # índices (pueden ya existir)
        try: cx.execute(text("CREATE UNIQUE INDEX IF NOT EXISTS uq_report_note_fp ON report_log (note_id, fingerprint)"))
        except Exception: pass
        try: cx.execute(text("CREATE UNIQUE INDEX IF NOT EXISTS uq_like_note_fp ON like_log (note_id, fingerprint)"))
        except Exception: pass
_bootstrap_db()

def _json(status: int, data: dict) -> Tuple[str, list, bytes]:
    body = json.dumps(data, default=str).encode("utf-8")
    status_line = f"{status} " + ("OK" if status == 200 else "ERROR")
    headers = [("Content-Type", "application/json; charset=utf-8"),
               ("Content-Length", str(len(body)))]
    return status_line, headers, body

def _html(status: int, body_html: str, ctype="text/html; charset=utf-8"):
    body = body_html.encode("utf-8")
    status_line = f"{status} " + ("OK" if status == 200 else "ERROR")
    headers = [("Content-Type", ctype), ("Content-Length", str(len(body)))]
    return status_line, headers, body
# P12 RETURNING GUARD HELPER (idempotent)
def _bump_note_counter(db, note_id, col):
    # col validada por whitelist para evitar SQL injection
    if col not in ("likes","views","reports"):
        return None
    try:
        cur = db.cursor()
        sql = f"UPDATE note SET {col}=COALESCE({col},0)+1 WHERE id=%s RETURNING COALESCE(likes,0), COALESCE(views,0), COALESCE(reports,0)"
        cur.execute(sql, (note_id,))
        row = cur.fetchone()
        cur.close()
        if not row:
            try:
                db.rollback()
            except Exception:
                pass
            return None
        try:
            db.commit()
        except Exception:
            pass
        return {"likes": row[0], "views": row[1], "reports": row[2]}
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        return None

def _finish(start_response, status, headers, body, method, extra_headers=None):
    try:
        # Normaliza body a bytes
        if isinstance(body, (bytes, bytearray)):
            body_bytes = bytes(body)
        elif body is None:
            body_bytes = b""
        elif isinstance(body, list):
            body_bytes = b"".join(x if isinstance(x,(bytes,bytearray)) else str(x).encode("utf-8") for x in body)
        elif isinstance(body, str):
            body_bytes = body.encode("utf-8")
        else:
            try:
                body_bytes = bytes(body)
            except Exception:
                body_bytes = str(body).encode("utf-8")

        # Inyecta meta p12-single si detecta body data-single
        try:
            body_bytes = _inject_single_meta(body_bytes)
        except Exception:
            pass

        # Unifica headers + extra y asegura Content-Length
        hdrs = list(headers or [])
        if extra_headers:
            hdrs.extend(list(extra_headers))
        if not any((k.lower() == "content-length") for k,_ in hdrs):
            hdrs.append(("Content-Length", str(len(body_bytes))))
        has_ct = None
        for k,v in hdrs:
            if k.lower() == "content-type":
                has_ct = v; break
        if has_ct is None and (body_bytes.startswith(b"<!doctype html") or b"<html" in body_bytes[:200]):
            hdrs.append(("Content-Type","text/html; charset=utf-8"))

        start_response(status, hdrs)
        return [body_bytes]
    except Exception:
        try:
            start_response("500 Internal Server Error", [("Content-Type","text/plain; charset=utf-8")])
        except Exception:
            pass
        return [b"internal error"]







# BEGIN:p12_bump_helper
def _bump_counter(db, note_id: int, field: str):
    if field not in ("likes", "views", "reports"):
        return False, {"ok": False, "error": "bad_field"}
    try:
        cur = db.cursor()
        sql = (
            "UPDATE note "
            f"SET {field}=COALESCE({field},0)+1 "
            "WHERE id=%s "
            "RETURNING id, COALESCE(likes,0), COALESCE(views,0), COALESCE(reports,0)"
        )
        cur.execute(sql, (note_id,))
        row = cur.fetchone()
        cur.close()
        if not row:
            try: db.rollback()
            except Exception: pass
            return False, {"ok": False, "error": "not_found"}
        try: db.commit()
        except Exception: pass
        return True, {"ok": True, "id": row[0], "likes": row[1], "views": row[2], "reports": row[3], "deduped": False}
    except Exception:
        try: db.rollback()
        except Exception: pass
        return False, {"ok": False, "error": "db_error"}
# END:p12_bump_helper

# === P12_DIAG_MW_V1: diag/import + deploy-stamp middleware (append-only, idempotente) ===
try:
    import os, json, datetime, re
    _inner_app = application  # conserva tu app original

    def _mask_db_url(u):
        try:
            return re.sub(r'://[^@]*@', '://****:****@', u or "")
        except Exception:
            return u or ""

    def _json_bytes(obj):
        return json.dumps(obj, ensure_ascii=False, indent=2).encode("utf-8")

    def _diag_app(environ, start_response):
        path = (environ.get("PATH_INFO") or "/")
        method = (environ.get("REQUEST_METHOD") or "GET").upper()

        # /api/deploy-stamp — pequeño JSON con commit y fecha de deploy
        if path == "/api/deploy-stamp":
            stamp = {
                "ok": True,
                "deploy": {
                    "commit": os.getenv("RENDER_GIT_COMMIT") or os.getenv("COMMIT_SHA") or os.getenv("SOURCE_VERSION") or "",
                    "date": os.getenv("RENDER_GIT_COMMIT_TIMESTAMP") or datetime.datetime.utcnow().isoformat()+"Z",
                }
            }
            body = _json_bytes(stamp)
            start_response("200 OK", [("Content-Type","application/json; charset=utf-8"),
                                      ("Cache-Control","no-store"), ("Content-Length", str(len(body)))])
            return [body]

        # /diag/import — snapshot JSON (habilitado por P12_DIAG=1; por defecto ON)
        if path == "/diag/import":
            allow = (os.getenv("P12_DIAG","1").lower() in ("1","true","yes","on"))
            if method == "OPTIONS":
                start_response("204 No Content", [("Content-Length","0"), ("Access-Control-Max-Age","86400")])
                return [b""]
            if not allow:
                # responde limpio, pero sin cuerpo (cierre explícito)
                start_response("204 No Content", [("Content-Length","0"), ("Cache-Control","no-store")])
                return [b""]

            keys = [
                "RENDER","RENDER_SERVICE_ID","RENDER_INSTANCE_ID","RENDER_EXTERNAL_URL",
                "RENDER_GIT_COMMIT","RENDER_GIT_COMMIT_TIMESTAMP",
                "PYTHON_VERSION","DATABASE_URL","SOURCE_VERSION","GIT_COMMIT","TZ"
            ]
            env = {}
            for k in keys:
                v = os.getenv(k, "")
                if k == "DATABASE_URL" and v:
                    v = _mask_db_url(v)
                env[k] = v

            payload = {
                "ok": True,
                "deploy": {
                    "commit": env.get("RENDER_GIT_COMMIT") or env.get("SOURCE_VERSION") or env.get("GIT_COMMIT") or "",
                    "date": env.get("RENDER_GIT_COMMIT_TIMESTAMP",""),
                },
                "env": env
            }
            body = _json_bytes(payload)
            start_response("200 OK", [("Content-Type","application/json; charset=utf-8"),
                                      ("Cache-Control","no-store"), ("Content-Length", str(len(body)))])
            return [body]

        # resto: pasa a tu app original
        return _inner_app(environ, start_response)

    application = _diag_app
except Exception:
    # En caso de error, no rompemos la app
    pass
# === /P12_DIAG_MW_V1 ===

# --- P12: exportar 'app' de forma robusta para entornos que arrancan con 'wsgiapp:app' ---
# Intenta backend.* y luego cae a la factoría local si existe.
try:
    app  # si ya existe, no hacemos nada
except NameError:
    from importlib import import_module
    import inspect

    def _p12_is_wsgi_function(obj):
        if not callable(obj) or inspect.isclass(obj):
            return False
        try:
            sig = inspect.signature(obj)
            names = [p.name.lower() for p in sig.parameters.values()
                     if p.kind in (p.POSITIONAL_ONLY, p.POSITIONAL_OR_KEYWORD)]
        except (ValueError, TypeError):
            return False
        return len(names) >= 2 and names[0] in ("environ","env") and names[1] == "start_response"

    def _p12_is_wsgi_object(obj):
        if inspect.isclass(obj):
            return False
        call = getattr(obj, "__call__", None)
        if call and callable(call):
            try:
                sig = inspect.signature(call)
                names = [p.name.lower() for p in sig.parameters.values()
                         if p.kind in (p.POSITIONAL_ONLY, p.POSITIONAL_OR_KEYWORD)]
                return len(names) >= 2 and names[0] in ("environ","env") and names[1] == "start_response"
            except (ValueError, TypeError):
                return False
        # frameworks como Flask suelen tener .wsgi_app y ser invocables
        return hasattr(obj, "wsgi_app") and callable(obj)

    def _p12_try_candidates():
        candidates = [
            ("backend.app", "app"),
            ("backend.main", "app"),
            ("backend.wsgi", "app"),
            ("app", "app"),
            ("run", "app"),
        ]
        for modname, attr in candidates:
            try:
                mod = import_module(modname)
                obj = getattr(mod, attr, None)
                if obj and (_p12_is_wsgi_function(obj) or _p12_is_wsgi_object(obj)):
                    return obj
            except Exception:
                pass
        return None

    _p12_target = _p12_try_candidates()

    if _p12_target is None:
        # último recurso: si este módulo define _resolve_app(), úsalo una sola vez
        try:
            _p12_factory = globals().get("_resolve_app")
            if callable(_p12_factory):
                maybe = _p12_factory()
                if maybe and (_p12_is_wsgi_function(maybe) or _p12_is_wsgi_object(maybe)):
                    _p12_target = maybe
        except Exception:
            _p12_target = None

    if _p12_target is None:
        raise RuntimeError("wsgiapp: no pude exportar 'app' (backend.* y factoría fallaron)")

    def app(environ, start_response):
        return _p12_target(environ, start_response)
# --- fin P12 ---

# --- P12 alias: exportar app desde entry_main para tolerar 'wsgiapp:app' ---
try:
    from entry_main import app as app
except Exception as e:
    raise RuntimeError(f"wsgiapp alias → entry_main:app falló: {e}")
# --- fin alias P12 ---

# --- P12 alias: exportar app desde entry_main para tolerar 'wsgiapp:app' ---
try:
    from entry_main import app as app
except Exception as e:
    raise RuntimeError(f"wsgiapp alias → entry_main:app falló: {e}")
# --- fin alias P12 ---

# --- P12: export robusto de WSGI app (tolerante a start antiguo o blueprint) ---
# Objetivo: garantizar que 'wsgiapp:app' y 'wsgiapp:application' EXISTAN y sean WSGI callables.
# 1) Si entry_main:app existe, úsalo.  2) Si no, probá con _resolve_app() legacy.  3) Si nada, 500 claro.

def _p12_resolve_wsgi_app():
    # Intento 1: entry_main:app (si está presente)
    try:
        from entry_main import app as entry_app
        if callable(entry_app):
            return entry_app
    except Exception:
        pass
    # Intento 2: resolver interno legacy (si existe)
    try:
        if '_resolve_app' in globals() and callable(_resolve_app):
            candidate = _resolve_app()
            if candidate:
                return candidate
    except Exception:
        pass
    return None

def app(environ, start_response):
    target = _p12_resolve_wsgi_app()
    if target is None:
        start_response('500 Internal Server Error', [('Content-Type','text/plain; charset=utf-8')])
        return [b'wsgiapp: no pude resolver la WSGI app (entry_main o _resolve_app)']
    return target(environ, start_response)

# Alias gunicorn convencional
application = app
# --- fin P12 export robusto ---


# === P12 CONTRACT SHIM EXPORT ===
try:
    from contract_shim import application as application, app as app
except Exception:
    pass
