import os, sys, json
from importlib import import_module

CANDIDATES = ["app:app", "run:app", "render_entry:app", "entry_main:app"]

def _resolve_app():
    last_err = None
    for spec in CANDIDATES:
        try:
            os.environ["APP_MODULE"] = spec
            if "patched_app" in sys.modules:
                del sys.modules["patched_app"]
            pa = import_module("patched_app")
            return getattr(pa, "app")
        except Exception as e:
            last_err = e
    raise RuntimeError(f"No pude resolver APP_MODULE (probados {CANDIDATES}). Último error: {last_err!r}")

# Bootstrap DB idempotente (solo Postgres)
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
                    timestamp TIMESTAMPTZ DEFAULT NOW(),
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

def _json(status_code: int, data: dict):
    body = json.dumps(data, default=str).encode("utf-8")
    status = f"{status_code} " + ("OK" if status_code == 200 else "ERROR")
    headers = [("Content-Type", "application/json; charset=utf-8"),
               ("Content-Length", str(len(body)))]
    return status, headers, body

def _finish(start_response, status, headers, body, method):
    if method == "HEAD":
        headers = [(k, ("0" if k.lower()=="content-length" else v)) for k,v in headers]
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

def _notes_query(qs):
    # Parámetros comunes para notes_fallback y notes
    from urllib.parse import parse_qs
    from sqlalchemy import text as _text
    try:
        params = parse_qs(qs or "", keep_blank_values=True)
        def _get(name, cast=lambda x:x, default=None):
            v = params.get(name, [None])[0]
            return default if v is None or v=="" else cast(v)
        limit     = max(1, min(_get("limit", int, 20), 100))
        cursor_ts = _get("cursor_ts", str, None)
        cursor_id = _get("cursor_id", int, None)

        with _engine().begin() as cx:
            if cursor_ts and cursor_id:
                q = _text("""
                    SELECT id, title, url, summary, content, timestamp, likes, views, reports
                    FROM note
                    WHERE (timestamp < :ts) OR (timestamp = :ts AND id < :id)
                    ORDER BY timestamp DESC, id DESC
                    LIMIT :lim
                """)
                rows = cx.execute(q, {"ts": cursor_ts, "id": cursor_id, "lim": limit}).mappings().all()
            else:
                q = _text("""
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
        return 200, {"ok": True, "items": items, "next": next_cursor}
    except Exception as e:
        return 500, {"ok": False, "error": str(e)}

def _middleware(inner_app):
    # Intercepta rutas y añade header a TODAS las respuestas
    def _app(environ, start_response):
        path   = environ.get("PATH_INFO", "")
        method = environ.get("REQUEST_METHOD", "GET").upper()
        qs     = environ.get("QUERY_STRING", "")

        # wrapper para inyectar header en todo lo que pase al app real
        def sr(status, headers, exc_info=None):
            headers = list(headers) + [("X-WSGI-Bridge", "1")]
            return start_response(status, headers, exc_info)

        # Auxiliares GET/HEAD
        if path == "/api/deploy-stamp" and method in ("GET","HEAD"):
            data = dict(
                ok=True,
                commit=os.environ.get("RENDER_GIT_COMMIT") or os.environ.get("COMMIT") or "",
                stamp=os.environ.get("DEPLOY_STAMP") or "",
            )
            status, headers, body = _json(200, data)
            headers.append(("X-WSGI-Bridge", "1"))
            return _finish(start_response, status, headers, body, method)

        if path in ("/api/notes_fallback", "/api/notes") and method in ("GET","HEAD"):
            code, payload = _notes_query(qs)
            status, headers, body = _json(code, payload)
            headers.append(("X-WSGI-Bridge", "1"))
            return _finish(start_response, status, headers, body, method)

        if path == "/api/notes_diag" and method in ("GET","HEAD"):
            from sqlalchemy import text as _text
            try:
                with _engine().begin() as cx:
                    dialect = cx.connection.engine.dialect.name
                    if dialect.startswith("sqlite"):
                        rows = cx.execute(_text("PRAGMA table_info(note)")).mappings().all()
                        cols = [dict(r) for r in rows]
                    else:
                        q = _text("""
                            SELECT column_name, data_type
                            FROM information_schema.columns
                            WHERE table_name = 'note'
                            ORDER BY ordinal_position
                        """)
                        cols = [dict(r) for r in cx.execute(q).mappings().all()]
                status, headers, body = _json(200, {"ok": True, "dialect": dialect, "columns": cols})
            except Exception as e:
                status, headers, body = _json(500, {"ok": False, "error": str(e)})
            headers.append(("X-WSGI-Bridge", "1"))
            return _finish(start_response, status, headers, body, method)

        # resto → app real, pero con header
        return inner_app(environ, sr)
    return _app

# app final
app = _middleware(_resolve_app())
