import os, sys, json
from importlib import import_module
from typing import Callable, Tuple

# --- asegurar repo en sys.path ---
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

# --- bootstrap DB idempotente (Postgres) ---
try:
    from sqlalchemy import create_engine, text
    url = os.environ.get("DATABASE_URL", "")
    if url.startswith("postgres"):
        eng = create_engine(url, pool_pre_ping=True)
        with eng.begin() as cx:
            cx.execute(text("""
                CREATE TABLE IF NOT EXISTS note(
                    id SERIAL PRIMARY KEY,
                    title TEXT,
                    url TEXT,
                    summary TEXT,
                    content TEXT,
                    text TEXT,
                    timestamp TIMESTAMPTZ DEFAULT NOW(),
                    expires_at TIMESTAMPTZ,
                    likes INT DEFAULT 0,
                    views INT DEFAULT 0,
                    reports INT DEFAULT 0,
                    author_fp VARCHAR(64)
                )
            """))
            cx.execute(text("ALTER TABLE note ADD COLUMN IF NOT EXISTS author_fp VARCHAR(64)"))
            cx.execute(text("CREATE INDEX IF NOT EXISTS idx_note_timestamp ON note (timestamp DESC, id DESC)"))
            cx.execute(text("CREATE INDEX IF NOT EXISTS idx_note_likes ON note (likes)"))
            cx.execute(text("CREATE INDEX IF NOT EXISTS idx_note_views ON note (views)"))
            cx.execute(text("CREATE INDEX IF NOT EXISTS idx_note_reports ON note (reports)"))
except Exception as e:
    print(f"[wsgiapp] Bootstrap DB omitido: {e}")

# --- utils JSON/WSGI ---
def _json(status: int, data: dict) -> Tuple[str, list, bytes]:
    body = json.dumps(data, default=str).encode("utf-8")
    status_line = f"{status} " + ("OK" if status == 200 else "ERROR")
    headers = [("Content-Type", "application/json; charset=utf-8"),
               ("Content-Length", str(len(body)))]
    return status_line, headers, body

def _finish(start_response, status, headers, body, method):
    headers = list(headers) + [("X-WSGI-Bridge", "1")]
    if method == "HEAD":
        headers = [(k, ("0" if k.lower() == "content-length" else v)) for k, v in headers]
        start_response(status, headers)
        return [b""]
    start_response(status, headers)
    return [body]

def _engine():
    from sqlalchemy import create_engine
    url = os.environ.get("SQLALCHEMY_DATABASE_URI") or os.environ.get("DATABASE_URL")
    if not url:
        raise RuntimeError("DATABASE_URL/SQLALCHEMY_DATABASE_URI no definido")
    return create_engine(url, pool_pre_ping=True)

def _columns(conn) -> set:
    """Devuelve set de nombres de columnas reales de note."""
    from sqlalchemy import text as _text
    dialect = conn.engine.dialect.name
    if dialect.startswith("sqlite"):
        rows = conn.execute(_text("PRAGMA table_info(note)")).mappings().all()
        return {r["name"] for r in rows}
    else:
        q = _text("""
            SELECT column_name
            FROM information_schema.columns
            WHERE table_name = 'note' AND table_schema = current_schema()
        """)
        rows = conn.execute(q).mappings().all()
        return {r["column_name"] for r in rows}

def _build_select(cols: set, with_where: bool) -> str:
    """Arma un SELECT portable según columnas disponibles."""
    # Campos comunes
    base = ["id", "timestamp", "likes", "views", "reports", "author_fp"]
    # Campos de modelo "texto"
    textish = ["text", "expires_at"]
    # Campos de modelo "artículo"
    article = ["title", "url", "summary", "content"]

    select_parts = []
    for c in base:
        select_parts.append(c if c in cols else f"NULL AS {c}")
    for c in textish:
        select_parts.append(c if c in cols else f"NULL AS {c}")
    for c in article:
        select_parts.append(c if c in cols else f"NULL AS {c}")

    select_clause = ", ".join(select_parts)
    where_clause = """
        WHERE (timestamp < :ts) OR (timestamp = :ts AND id < :id)
    """ if with_where else ""

    return f"""
        SELECT {select_clause}
        FROM note
        {where_clause}
        ORDER BY timestamp DESC, id DESC
        LIMIT :lim
    """

def _normalize_row(r: dict) -> dict:
    """Devuelve un payload amplio compatible con ambos UIs."""
    # Garantizamos las claves presentes (faltantes a None)
    keys = ["id","text","title","url","summary","content",
            "timestamp","expires_at","likes","views","reports","author_fp"]
    out = {k: r.get(k) for k in keys}
    # Si no hay text pero sí content/summary, arma un texto de cortesía
    if not out.get("text"):
        out["text"] = out.get("content") or out.get("summary")
    return out

def _notes_query(qs: str):
    from urllib.parse import parse_qs
    from sqlalchemy import text as _text
    try:
        params = parse_qs(qs or "", keep_blank_values=True)
        def _get(name, cast=lambda x:x, default=None):
            v = params.get(name, [None])[0]
            return default if v is None or v == "" else cast(v)
        limit     = max(1, min(_get("limit", int, 20), 100))
        cursor_ts = _get("cursor_ts", str, None)
        cursor_id = _get("cursor_id", int, None)

        with _engine().begin() as cx:
            cols = _columns(cx)
            sql = _build_select(cols, with_where=bool(cursor_ts and cursor_id))
            args = {"lim": limit}
            if cursor_ts and cursor_id:
                args.update({"ts": cursor_ts, "id": cursor_id})
            rows = cx.execute(_text(sql), args).mappings().all()

        items = [_normalize_row(dict(r)) for r in rows]
        next_cursor = None
        if items:
            last = items[-1]
            if last.get("timestamp") is not None and last.get("id") is not None:
                next_cursor = {"cursor_ts": str(last["timestamp"]), "cursor_id": last["id"]}
        return 200, {"ok": True, "items": items, "next": next_cursor}
    except Exception as e:
        return 500, {"ok": False, "error": str(e)}

def _middleware(inner_app: Callable) -> Callable:
    from sqlalchemy import text as _text
    def _app(environ, start_response):
        path   = environ.get("PATH_INFO", "")
        method = environ.get("REQUEST_METHOD", "GET").upper()
        qs     = environ.get("QUERY_STRING", "")

        if path == "/api/deploy-stamp" and method in ("GET","HEAD"):
            data = {
                "ok": True,
                "commit": os.environ.get("RENDER_GIT_COMMIT") or os.environ.get("COMMIT") or "",
                "stamp": os.environ.get("DEPLOY_STAMP") or "",
            }
            status, headers, body = _json(200, data)
            return _finish(start_response, status, headers, body, method)

        if path in ("/api/notes", "/api/notes_fallback") and method in ("GET","HEAD"):
            code, payload = _notes_query(qs)
            status, headers, body = _json(code, payload)
            return _finish(start_response, status, headers, body, method)

        if path == "/api/notes_diag" and method in ("GET","HEAD"):
            try:
                with _engine().begin() as cx:
                    dialect = cx.engine.dialect.name
                    if dialect.startswith("sqlite"):
                        cols = [dict(r) for r in cx.execute(_text("PRAGMA table_info(note)")).mappings().all()]
                    else:
                        q = _text("""
                            SELECT column_name, data_type
                            FROM information_schema.columns
                            WHERE table_name = 'note' AND table_schema = current_schema()
                            ORDER BY ordinal_position
                        """)
                        cols = [dict(r) for r in cx.execute(q).mappings().all()]
                status, headers, body = _json(200, {"ok": True, "dialect": dialect, "columns": cols})
            except Exception as e:
                status, headers, body = _json(500, {"ok": False, "error": str(e)})
            return _finish(start_response, status, headers, body, method)

        return inner_app(environ, start_response)
    return _app

def _fallback_app():
    def _app(environ, start_response):
        path   = environ.get("PATH_INFO", "")
        method = environ.get("REQUEST_METHOD", "GET").upper()
        if path == "/api/health":
            status, headers, body = _json(200, {"ok": True, "note": "fallback"})
            return _finish(start_response, status, headers, body, method)
        status, headers, body = _json(503, {"ok": False, "error": "app not resolved"})
        return _finish(start_response, status, headers, body, method)
    return _app

_inner = _resolve_app() or _fallback_app()
app    = _middleware(_inner)
