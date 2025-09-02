import os, sys, json, mimetypes
from importlib import import_module
from typing import Callable, Tuple
from datetime import datetime, timedelta, timezone

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

# --- utils JSON/HTML/WSGI ---
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

def _finish(start_response, status, headers, body, method):
    headers = list(headers) + [("X-WSGI-Bridge", "1")]
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

# -------- notas: columnas dinámicas / payload unificado --------
def _columns(conn) -> set:
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
    base = ["id", "timestamp", "likes", "views", "reports", "author_fp"]
    textish = ["text", "expires_at"]
    article = ["title", "url", "summary", "content"]
    parts = []
    for c in base + textish + article:
        parts.append(c if c in cols else f"NULL AS {c}")
    where = "WHERE (timestamp < :ts) OR (timestamp = :ts AND id < :id)" if with_where else ""
    return f"SELECT {', '.join(parts)} FROM note {where} ORDER BY timestamp DESC, id DESC LIMIT :lim"

def _normalize_row(r: dict) -> dict:
    keys = ["id","text","title","url","summary","content","timestamp","expires_at","likes","views","reports","author_fp"]
    out = {k: r.get(k) for k in keys}
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
            return default if v is None or v=="" else cast(v)
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

def _insert_note(payload: dict):
    """Fallback de POST /api/notes: inserta una nota minimal y setea contadores=0 si existen."""
    from sqlalchemy import text as _text
    text_val = (payload.get("text") or "").strip()
    if not text_val:
        return 400, {"ok": False, "error": "text_required"}
    try:
        ttl_hours = int(payload.get("ttl_hours") or os.environ.get("NOTE_TTL_HOURS", "12") or "12")
    except Exception:
        ttl_hours = 12
    ttl_hours = 12 if ttl_hours <= 0 else ttl_hours
    now = datetime.now(timezone.utc)
    exp = now + timedelta(hours=ttl_hours)
    try:
        with _engine().begin() as cx:
            cols = _columns(cx)
            body_col = "text" if "text" in cols else ("content" if "content" in cols else ("summary" if "summary" in cols else None))
            if body_col is None:
                return 500, {"ok": False, "error": "no_textual_column"}

            fields, marks, args = [body_col], [":body"], {"body": text_val}

            # Timestamps / autor
            if "timestamp" in cols:
                fields.append("timestamp"); marks.append(":ts"); args["ts"] = now
            if "expires_at" in cols:
                fields.append("expires_at"); marks.append(":exp"); args["exp"] = exp
            if "author_fp" in cols:
                fields.append("author_fp"); marks.append(":fp"); args["fp"] = payload.get("author_fp")

            # CONTADORES: si existen, los seteamos explícitamente a 0 (evita NOT NULL sin DEFAULT)
            for c in ("likes","views","reports"):
                if c in cols:
                    fields.append(c); marks.append(f":{c}"); args[c] = 0

            sql = f"INSERT INTO note({', '.join(fields)}) VALUES ({', '.join(marks)})"
            # Intentar RETURNING id (PG)
            id_val = None
            try:
                row = cx.execute(_text(sql + " RETURNING id"), args).first()
                if row: id_val = row[0]
            except Exception:
                cx.execute(_text(sql), args)
                try:
                    id_val = cx.execute(_text("SELECT lastval()")).scalar()
                except Exception:
                    id_val = cx.execute(_text("SELECT MAX(id) FROM note")).scalar()

            # Leer la fila creada
            cols2 = _columns(cx)
            sel = _build_select(cols2, with_where=False) + " OFFSET 0"
            row = cx.execute(_text(f"SELECT * FROM ({sel}) x WHERE id=:id"), {"id": id_val, "lim": 1}).mappings().first()
            item = _normalize_row(dict(row)) if row else {"id": id_val, "text": text_val}
        return 201, {"ok": True, "item": item}
    except Exception as e:
        return 500, {"ok": False, "error": str(e)}

def _try_read(path):
    try:
        with open(path, "rb") as f:
            return f.read()
    except Exception:
        return None

def _serve_index_html():
    override = os.environ.get("WSGI_BRIDGE_INDEX")
    candidates = [override] if override else [
        os.path.join(_REPO_DIR, "public", "index.html"),
        os.path.join(_REPO_DIR, "frontend", "index.html"),
        os.path.join(_REPO_DIR, "backend", "static", "index.html"),
        os.path.join(_REPO_DIR, "index.html"),
    ]
    for p in candidates:
        if p and os.path.isfile(p):
            body = _try_read(p)
            if body is not None:
                ctype = mimetypes.guess_type(p)[0] or "text/html"
                return _html(200, body.decode("utf-8", "ignore"), f"{ctype}; charset=utf-8")
    html = """<!doctype html>
<html><head><meta charset="utf-8"><title>paste12</title></head>
<body style="font-family: system-ui, sans-serif; margin: 2rem;">
<h1>paste12</h1>
<p>Backend vivo (bridge). Endpoints:</p>
<ul>
  <li><a href="/api/notes">/api/notes</a></li>
  <li><a href="/api/notes_fallback">/api/notes_fallback</a></li>
  <li><a href="/api/notes_diag">/api/notes_diag</a></li>
  <li><a href="/api/deploy-stamp">/api/deploy-stamp</a></li>
</ul>
</body></html>"""
    return _html(200, html)

def _middleware(inner_app: Callable) -> Callable:
    def _app(environ, start_response):
        path   = environ.get("PATH_INFO", "")
        method = environ.get("REQUEST_METHOD", "GET").upper()
        qs     = environ.get("QUERY_STRING", "")

        # raíz: SIEMPRE servimos nuestro index (evita duplicados)
        if path in ("/", "/index.html") and method in ("GET","HEAD"):
            status, headers, body = _serve_index_html()
            return _finish(start_response, status, headers, body, method)

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

        if path == "/api/notes" and method == "POST":
            try:
                ctype = environ.get("CONTENT_TYPE","")
                length = int(environ.get("CONTENT_LENGTH","0") or "0")
                raw = environ["wsgi.input"].read(length) if length > 0 else b""
                data = {}
                if "application/json" in ctype:
                    try: data = json.loads(raw.decode("utf-8") or "{}")
                    except Exception: data = {}
                else:
                    try:
                        from urllib.parse import parse_qs
                        qd = parse_qs(raw.decode("utf-8"), keep_blank_values=True)
                        data = {k: v[0] for k,v in qd.items()}
                    except Exception:
                        data = {}
                code, payload = _insert_note(data)
            except Exception as e:
                code, payload = 500, {"ok": False, "error": str(e)}
            status, headers, body = _json(code, payload)
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

_inner = _resolve_app()
if _inner is None:
    _inner = _fallback_app()
app = _middleware(_inner)
__all__ = ["app"]
